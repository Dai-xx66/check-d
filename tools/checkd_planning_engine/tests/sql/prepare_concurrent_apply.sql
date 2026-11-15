begin;
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('80000000-0000-4000-8000-000000000001','authenticated','authenticated','concurrent@example.invalid','',now(),'{}','{}',now(),now());
insert into public.tasks(id,user_id,name,type,color)
values('81000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001','Concurrent synthetic task','one_time',1);
insert into public.agent_user_snapshot_versions(user_id,snapshot_version,computed_at,source_digest)
values('80000000-0000-4000-8000-000000000001','concurrent-v1',now(),'concurrency-fixture');
do $$ declare v_changes jsonb; v_digest text; begin
  v_changes:=jsonb_build_array(jsonb_build_object(
    'id','82000000-0000-4000-8000-000000000001',
    'task_id','81000000-0000-4000-8000-000000000001',
    'starts_at','2030-02-01T10:00:00Z','ends_at','2030-02-01T10:30:00Z','planned_seconds',1800));
  v_digest:=pg_catalog.encode(extensions.digest(v_changes::text,'sha256'),'hex');
  insert into public.agent_plan_proposals(id,user_id,base_version,changes,change_digest,rules_version,starts_on,ends_on,status,expires_at,idempotency_key)
  values('83000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001','concurrent-v1',v_changes,v_digest,'rules-v1','2030-02-01','2030-02-01','approved',now()+interval '5 minutes','concurrent-key');
  insert into public.agent_plan_approvals(id,user_id,proposal_id,base_version,change_digest,status,expires_at)
  values('84000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001','83000000-0000-4000-8000-000000000001','concurrent-v1',v_digest,'approved',now()+interval '5 minutes');
end $$;
commit;
