-- Isolated local Supabase integration check. All fixtures are rolled back.
begin;
do $$
declare
  u constant uuid := '81000000-0000-4000-8000-000000000001';
  d constant uuid := '82000000-0000-4000-8000-000000000001';
  t constant uuid := '83000000-0000-4000-8000-000000000001';
  p uuid;
  a uuid;
  snap jsonb;
  proposed jsonb;
  approved jsonb;
  applied jsonb;
  replay jsonb;
  stale_task constant uuid := '83000000-0000-4000-8000-000000000002';
  stale_proposal jsonb;
  start_time constant timestamptz := '2030-01-05 10:00:00+08';
  changes jsonb;
begin
  insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at)
  values(u,'authenticated','authenticated','planning-rpc-fixture@example.invalid','',now());
  insert into public.tasks(id,user_id,name,type,color)
  values(t,u,'fixture one-time task','one_time',1),
        (stale_task,u,'stale proposal fixture','one_time',1);
  insert into public.one_time_reminders(task_id,user_id,scheduled_at,has_scheduled_date,is_timed,
    available_from,planned_date,due_date)
  values(t,u,start_time,true,true,'2030-01-01','2030-01-05','2030-01-10'),
        (stale_task,u,start_time,true,true,'2030-01-01','2030-01-05','2030-01-10');
  insert into public.task_effort_estimates(user_id,task_id,estimated_seconds,remaining_seconds,source)
  values(u,t,1800,1800,'fixture_user_confirmed');
  insert into public.agent_device_sync_watermarks(user_id,device_id,acknowledged_generation)
  values(u,d,4);
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  snap:=public.build_agent_planning_snapshot('2030-01-05','2030-01-05');
  if snap->>'user_id'<>u::text or snap->>'execution_eligible'<>'false' then
    raise exception 'server snapshot did not bind caller identity or preserve non-production status';
  end if;
  changes:=jsonb_build_array(jsonb_build_object('task_id',t,'starts_at','2030-01-05T02:00:00Z',
    'ends_at','2030-01-05T02:30:00Z','planned_seconds',1800));
  proposed:=public.create_agent_plan_proposal('2030-01-05','2030-01-05',snap->>'snapshot_version',d,4,
    'planning_rules_v1','rpc-idempotency-01',changes);
  p:=(proposed->>'proposal_id')::uuid;
  if proposed->>'status'<>'proposed' or proposed->>'execution_eligible'<>'false' then
    raise exception 'proposal should be a non-production proposed record';
  end if;
  approved:=public.approve_agent_plan_proposal(p);
  a:=(approved->>'approval_id')::uuid;
  if approved->>'simulated_approval'<>'true' then raise exception 'test approval disclosure missing'; end if;
  applied:=public.apply_approved_plan(p,a,'rpc-apply-idempotency-01');
  if applied->>'readback_verified'<>'true' or applied->>'block_count'<>'1' then
    raise exception 'atomic apply/readback did not verify one planned block: %',applied;
  end if;
  replay:=public.apply_approved_plan(p,a,'rpc-apply-idempotency-01');
  if replay<>applied then raise exception 'same-key retry changed result'; end if;
  if (select count(*) from public.task_time_blocks where user_id=u and task_id=t)<>1 then
    raise exception 'idempotent retry duplicated business block';
  end if;

  -- A source edit after Proposal creation must prevent its approval.
  snap:=public.build_agent_planning_snapshot('2030-01-05','2030-01-05');
  stale_proposal:=public.create_agent_plan_proposal('2030-01-05','2030-01-05',
    snap->>'snapshot_version',d,4,'planning_rules_v1','rpc-stale-proposal-01',
    jsonb_build_array(jsonb_build_object('task_id',stale_task,'starts_at','2030-01-05T03:00:00Z',
      'ends_at','2030-01-05T03:30:00Z','planned_seconds',1800)));
  execute 'reset role';
  update public.tasks set name='source changed after proposal',updated_at=now()
    where id=stale_task and user_id=u;
  execute 'set local role authenticated';
  begin
    perform public.approve_agent_plan_proposal((stale_proposal->>'proposal_id')::uuid);
    raise exception 'stale proposal unexpectedly approved';
  exception when sqlstate 'P0001' then
    if sqlerrm<>'PROPOSAL_NOT_APPROVABLE' then raise; end if;
  end;
  if (select count(*) from public.task_time_blocks where user_id=u and task_id=stale_task)<>0 then
    raise exception 'stale proposal wrote a plan block';
  end if;
  execute 'reset role';
end $$;
rollback;
