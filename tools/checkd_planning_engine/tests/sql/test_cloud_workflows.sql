-- Run ONLY against the isolated Supabase project with:
-- docker exec -i supabase_db_checkd-planning-sync-validation psql -U postgres -d postgres -v ON_ERROR_STOP=1 < this file
-- All synthetic rows are rolled back at the end.
begin;

do $$
declare
  user_a constant uuid := '10000000-0000-4000-8000-000000000001';
  user_b constant uuid := '10000000-0000-4000-8000-000000000002';
  task_a constant uuid := '20000000-0000-4000-8000-000000000001';
  proposal_a constant uuid := '30000000-0000-4000-8000-000000000001';
  approval_a constant uuid := '40000000-0000-4000-8000-000000000001';
  proposal_b constant uuid := '30000000-0000-4000-8000-000000000004';
  proposal_expired constant uuid := '30000000-0000-4000-8000-000000000005';
  approval_expired constant uuid := '40000000-0000-4000-8000-000000000005';
  proposal_competing constant uuid := '30000000-0000-4000-8000-000000000007';
  approval_competing constant uuid := '40000000-0000-4000-8000-000000000007';
  proposal_token_expired constant uuid := '30000000-0000-4000-8000-000000000006';
  approval_token_expired constant uuid := '40000000-0000-4000-8000-000000000006';
  proposal_conflict constant uuid := '30000000-0000-4000-8000-000000000002';
  approval_conflict constant uuid := '40000000-0000-4000-8000-000000000002';
  proposal_fail constant uuid := '30000000-0000-4000-8000-000000000003';
  approval_fail constant uuid := '40000000-0000-4000-8000-000000000003';
  changes_a jsonb := jsonb_build_array(jsonb_build_object(
    'id','50000000-0000-4000-8000-000000000001',
    'task_id',task_a,
    'starts_at','2030-01-01T10:00:00Z',
    'ends_at','2030-01-01T10:30:00Z',
    'planned_seconds',1800
  ));
  digest_a text;
  digest_competing text;
  changes_competing jsonb;
  result_a jsonb;
  risk_result jsonb;
  found_count integer;
  event_a public.agent_risk_events%rowtype;
  stale_lease uuid;
begin
  insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values
    (user_a,'authenticated','authenticated','planning-a@example.invalid','',now(),'{}','{}',now(),now()),
    (user_b,'authenticated','authenticated','planning-b@example.invalid','',now(),'{}','{}',now(),now());
  insert into public.tasks(id,user_id,name,type,color)
    values(task_a,user_a,'Synthetic planning task','one_time',1);
  insert into public.agent_user_snapshot_versions(user_id,snapshot_version,computed_at,source_digest)
    values(user_a,'snapshot-a-v1',now(),'fixture'),(user_b,'snapshot-b-v1',now(),'fixture');

  digest_a := pg_catalog.encode(extensions.digest(changes_a::text,'sha256'),'hex');
  insert into public.agent_plan_proposals(id,user_id,base_version,changes,change_digest,rules_version,
    starts_on,ends_on,status,expires_at,idempotency_key)
  values(proposal_a,user_a,'snapshot-a-v1',changes_a,digest_a,'fixture-rules',
    '2030-01-01','2030-01-01','approved',now()+interval '10 minutes','fixture-apply-a');
  insert into public.agent_plan_approvals(id,user_id,proposal_id,base_version,change_digest,status,expires_at)
  values(approval_a,user_a,proposal_a,'snapshot-a-v1',digest_a,'approved',now()+interval '5 minutes');
  insert into public.agent_plan_proposals(id,user_id,base_version,changes,change_digest,rules_version,
    starts_on,ends_on,status,expires_at,idempotency_key)
  values(proposal_b,user_b,'snapshot-b-v1',changes_a,digest_a,'fixture-rules',
    '2030-01-01','2030-01-01','approved',now()+interval '10 minutes','fixture-apply-b');

  -- Verified identity context, with no request-body user_id.
  perform set_config('request.jwt.claim.sub',user_a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',user_a,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  result_a := public.apply_approved_plan(proposal_a,approval_a,'fixture-apply-a');
  execute 'reset role';
  if result_a->>'readback_verified' <> 'true' or result_a->>'block_count' <> '1' then
    raise exception 'successful apply did not return verified readback';
  end if;
  if (select snapshot_version from public.agent_user_snapshot_versions where user_id=user_a) = 'snapshot-a-v1' then
    raise exception 'successful apply did not rotate the snapshot concurrency fence';
  end if;
  changes_competing:=jsonb_build_array(jsonb_build_object(
    'id','50000000-0000-4000-8000-000000000002','task_id',task_a,
    'starts_at','2030-01-01T12:00:00Z','ends_at','2030-01-01T12:30:00Z','planned_seconds',1800));
  digest_competing:=pg_catalog.encode(extensions.digest(changes_competing::text,'sha256'),'hex');
  insert into public.agent_plan_proposals(id,user_id,base_version,changes,change_digest,rules_version,starts_on,ends_on,status,expires_at,idempotency_key)
    values(proposal_competing,user_a,'snapshot-a-v1',changes_competing,digest_competing,'fixture-rules','2030-01-01','2030-01-01','approved',now()+interval '10 minutes','fixture-competing');
  insert into public.agent_plan_approvals(id,user_id,proposal_id,base_version,change_digest,status,expires_at)
    values(approval_competing,user_a,proposal_competing,'snapshot-a-v1',digest_competing,'approved',now()+interval '5 minutes');
  begin
    execute 'set local role authenticated';
    perform public.apply_approved_plan(proposal_competing,approval_competing,'fixture-competing');
    raise exception 'competing stale proposal unexpectedly applied';
  exception when serialization_failure then null;
  end;
  if exists(select 1 from public.agent_plan_apply_idempotency where user_id=user_a and idempotency_key='fixture-competing') then
    raise exception 'stale competing proposal created an idempotency row'; end if;
  execute 'set local role authenticated';
  if public.apply_approved_plan(proposal_a,approval_a,'fixture-apply-a') <> result_a then
    raise exception 'idempotent retry changed result';
  end if;
  execute 'reset role';
  begin
    execute 'set local role authenticated';
    perform public.apply_approved_plan(proposal_a,approval_a,'different-key');
    raise exception 'new key unexpectedly reapplied an applied proposal';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'ALREADY_APPLIED' then raise; end if;
  end;

  -- Cross-user proposal IDs are opaque and return NOT_FOUND.
  begin
    execute 'set local role authenticated';
    perform public.apply_approved_plan(proposal_b,approval_a,'cross-user');
    raise exception 'cross-user proposal unexpectedly applied';
  exception when sqlstate 'P0002' then
    if sqlerrm <> 'NOT_FOUND' then raise; end if;
  end;

  insert into public.agent_plan_proposals(id,user_id,base_version,changes,change_digest,rules_version,
    starts_on,ends_on,status,expires_at,idempotency_key)
  values(proposal_expired,user_a,'snapshot-a-v1',changes_a,digest_a,'fixture-rules',
    '2030-01-01','2030-01-01','approved',now(),'fixture-expired');
  insert into public.agent_plan_approvals(id,user_id,proposal_id,base_version,change_digest,status,expires_at)
  values(approval_expired,user_a,proposal_expired,'snapshot-a-v1',digest_a,'approved',now()+interval '5 minutes');
  begin
    execute 'set local role authenticated';
    perform public.apply_approved_plan(proposal_expired,approval_expired,'fixture-expired');
    raise exception 'expired proposal unexpectedly applied';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'PROPOSAL_EXPIRED' then raise; end if;
  end;
  insert into public.agent_plan_proposals(id,user_id,base_version,changes,change_digest,rules_version,
    starts_on,ends_on,status,expires_at,idempotency_key)
  values(proposal_token_expired,user_a,'snapshot-a-v1',changes_a,digest_a,'fixture-rules',
    '2030-01-01','2030-01-01','approved',now()+interval '10 minutes','fixture-token-expired');
  insert into public.agent_plan_approvals(id,user_id,proposal_id,base_version,change_digest,status,expires_at)
  values(approval_token_expired,user_a,proposal_token_expired,'snapshot-a-v1',digest_a,'approved',now());
  begin
    execute 'set local role authenticated';
    perform public.apply_approved_plan(proposal_token_expired,approval_token_expired,'fixture-token-expired');
    raise exception 'expired approval unexpectedly applied';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'APPROVAL_EXPIRED' then raise; end if;
  end;

  -- A changed trusted snapshot invalidates an otherwise approved proposal and writes nothing.
  update public.agent_user_snapshot_versions set snapshot_version='snapshot-a-v2' where user_id=user_a;
  insert into public.agent_plan_proposals(id,user_id,base_version,changes,change_digest,rules_version,
    starts_on,ends_on,status,expires_at,idempotency_key)
  values(proposal_conflict,user_a,'snapshot-a-v1',changes_a,digest_a,'fixture-rules',
    '2030-01-01','2030-01-01','approved',now()+interval '10 minutes','fixture-conflict');
  insert into public.agent_plan_approvals(id,user_id,proposal_id,base_version,change_digest,status,expires_at)
  values(approval_conflict,user_a,proposal_conflict,'snapshot-a-v1',digest_a,'approved',now()+interval '5 minutes');
  begin
    execute 'set local role authenticated';
    perform public.apply_approved_plan(proposal_conflict,approval_conflict,'fixture-conflict');
    raise exception 'stale snapshot unexpectedly applied';
  exception when serialization_failure then null;
  end;
  if exists(select 1 from public.agent_plan_apply_idempotency where user_id=user_a and idempotency_key='fixture-conflict') then
    raise exception 'snapshot conflict left an idempotency write';
  end if;

  -- Invalid FK during application rolls back proposal, approval, version and idempotency mutations.
  changes_a := jsonb_build_array(jsonb_build_object(
    'id','50000000-0000-4000-8000-000000000003',
    'task_id','20000000-0000-4000-8000-000000000099',
    'starts_at','2030-01-01T11:00:00Z','ends_at','2030-01-01T11:30:00Z','planned_seconds',1800));
  digest_a := pg_catalog.encode(extensions.digest(changes_a::text,'sha256'),'hex');
  insert into public.agent_plan_proposals(id,user_id,base_version,changes,change_digest,rules_version,
    starts_on,ends_on,status,expires_at,idempotency_key)
  values(proposal_fail,user_a,'snapshot-a-v2',changes_a,digest_a,'fixture-rules',
    '2030-01-01','2030-01-01','approved',now()+interval '10 minutes','fixture-fail');
  insert into public.agent_plan_approvals(id,user_id,proposal_id,base_version,change_digest,status,expires_at)
  values(approval_fail,user_a,proposal_fail,'snapshot-a-v2',digest_a,'approved',now()+interval '5 minutes');
  begin
    execute 'set local role authenticated';
    perform public.apply_approved_plan(proposal_fail,approval_fail,'fixture-fail');
    raise exception 'invalid task FK unexpectedly applied';
  exception when foreign_key_violation then null;
  end;
  if (select status from public.agent_plan_proposals where id=proposal_fail) <> 'approved'
     or (select status from public.agent_plan_approvals where id=approval_fail) <> 'approved'
     or exists(select 1 from public.agent_plan_apply_idempotency where user_id=user_a and idempotency_key='fixture-fail') then
    raise exception 'failed apply did not roll back atomically';
  end if;

  -- Per-user risk-event dedupe is isolated and retry leases recover.
  insert into public.agent_risk_events(user_id,dedupe_key,event_type,payload)
    values(user_a,'risk-scan-1','risk_scan','{}'),(user_b,'risk-scan-1','risk_scan','{}');
  select count(*) into found_count from public.agent_risk_events where dedupe_key='risk-scan-1';
  if found_count <> 2 then raise exception 'risk event dedupe crossed user boundary'; end if;
  select count(*) into found_count from public.claim_agent_risk_events(10);
  if found_count <> 2 then raise exception 'worker did not claim both isolated events'; end if;
  select * into event_a from public.agent_risk_events where user_id=user_a and dedupe_key='risk-scan-1';
  stale_lease:=event_a.lease_token;
  update public.agent_risk_events set status='retry',next_retry_at=now()-interval '1 second',lease_until=null
    where dedupe_key='risk-scan-1' and user_id=user_a;
  select count(*) into found_count from public.claim_agent_risk_events(10);
  if found_count <> 1 then raise exception 'risk retry was not reclaimed'; end if;
  select * into event_a from public.agent_risk_events where user_id=user_a and dedupe_key='risk-scan-1';
  if event_a.lease_token=stale_lease then raise exception 'reclaim did not rotate the fencing token'; end if;
  if public.finish_agent_risk_event(event_a.id,stale_lease,null,null,'{}') <> 'lease_lost' then
    raise exception 'stale worker was not fenced'; end if;
  if public.finish_agent_risk_event(event_a.id,event_a.lease_token,'SYNTHETIC_FAILURE',now()-interval '1 second',null,3) <> 'retry' then
    raise exception 'transient worker failure was not retryable'; end if;
  select count(*) into found_count from public.claim_agent_risk_events(10);
  if found_count <> 1 then raise exception 'expired retry event was not reclaimed'; end if;
  select * into event_a from public.agent_risk_events where user_id=user_a and dedupe_key='risk-scan-1';
  if public.finish_agent_risk_event(event_a.id,event_a.lease_token,null,null,'{"evaluated":true}') <> 'done' then
    raise exception 'successful worker completion was not persisted'; end if;
  if (select status from public.agent_risk_events where id=event_a.id) <> 'done' then
    raise exception 'risk event did not reach done'; end if;

  execute 'set local role service_role';
  risk_result:=public.persist_agent_risk_snapshot(user_a,'risk-snapshot-a-v1',
    '[{"risk_key":"deadline-buffer-task","risk_type":"deadline_buffer_low","severity":"high","payload":{"task_id":"fixture-a"}}]'::jsonb);
  if risk_result->>'notifications_queued'<>'1' then raise exception 'initial risk notification not queued'; end if;
  risk_result:=public.persist_agent_risk_snapshot(user_b,'risk-snapshot-b-v1',
    '[{"risk_key":"deadline-buffer-task","risk_type":"deadline_buffer_low","severity":"high","payload":{"task_id":"fixture-b"}}]'::jsonb);
  if risk_result->>'notifications_queued'<>'1' then raise exception 'other user risk notification not isolated'; end if;
  execute 'reset role';
  execute 'set local role authenticated';
  if not public.dismiss_agent_risk('deadline-buffer-task',interval '12 hours') then
    raise exception 'owner could not dismiss risk'; end if;
  execute 'reset role';
  execute 'set local role service_role';
  risk_result:=public.persist_agent_risk_snapshot(user_a,'risk-snapshot-a-v2',
    '[{"risk_key":"deadline-buffer-task","risk_type":"deadline_buffer_low","severity":"high","payload":{"task_id":"fixture-a"}}]'::jsonb);
  if risk_result->>'notifications_queued'<>'0' then raise exception 'dismissed risk ignored cooldown'; end if;
  update public.agent_risk_states set cooldown_until=now()-interval '1 second'
    where user_id=user_a and risk_key='deadline-buffer-task';
  risk_result:=public.persist_agent_risk_snapshot(user_a,'risk-snapshot-a-v2-expired-cooldown',
    '[{"risk_key":"deadline-buffer-task","risk_type":"deadline_buffer_low","severity":"high","payload":{"task_id":"fixture-a"}}]'::jsonb);
  if risk_result->>'notifications_queued'<>'1' then raise exception 'risk did not re-alert after cooldown'; end if;
  risk_result:=public.persist_agent_risk_snapshot(user_a,'risk-snapshot-a-v3',
    '[{"risk_key":"deadline-buffer-task","risk_type":"deadline_buffer_low","severity":"critical","payload":{"task_id":"fixture-a"}}]'::jsonb);
  if risk_result->>'notifications_queued'<>'1' then raise exception 'critical escalation did not bypass cooldown'; end if;
  perform public.persist_agent_risk_snapshot(user_a,'risk-snapshot-a-v4','[]'::jsonb);
  execute 'reset role';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub',user_a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',user_a,'role','authenticated')::text,true);
  select count(*) into found_count from public.agent_risk_states;
  if found_count <> 1 then raise exception 'risk RLS did not isolate user A'; end if;
  if (select status from public.agent_risk_states where user_id=user_a and risk_key='deadline-buffer-task') <> 'resolved' then
    raise exception 'risk disappearing from snapshot was not resolved'; end if;
  reset role;
end $$;

rollback;
