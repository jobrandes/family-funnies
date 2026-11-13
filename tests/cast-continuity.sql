begin;
do $$
declare fid uuid;pid uuid;rid bigint;cid uuid;ec uuid;ac uuid;today date:=(now() at time zone 'America/Los_Angeles')::date;
begin
 insert into families(name) values('Synthetic continuity test') returning id into fid;
 insert into people(family_id,name) values(fid,'Approved Person') returning id into pid;
 select visual_revision into rid from families where id=fid;
 insert into cast_versions(family_id,visual_revision,object_path,approved_at,approved_by) values(fid,rid,fid||'/approved.png',now(),'synthetic-owner') returning id into ac;
 update families set production_enabled=true where id=fid;
 insert into people(family_id,name,kind,memorial) values(fid,'New Memorial Pet','pet',true);
 select visual_revision into rid from families where id=fid;
 if not (select production_enabled from families where id=fid) then raise exception 'Additive update interrupted production';end if;
 ec:=(public.runner_command(command=>'episode_claim',fid=>fid,revision=>rid,target_day=>today)->>'claimId')::uuid;
 if not exists(select 1 from episode_jobs where family_id=fid and approved_cast_id=ac) then raise exception 'Approved cast not pinned';end if;
 perform public.runner_command(command=>'episode_complete',fid=>fid,revision=>rid,claim=>ec,target_day=>today,object_path=>fid||'/comic.png',title=>'Synthetic',script=>'Approved people only');
 if exists(select 1 from cast_versions where family_id=fid and visual_revision=rid and approved_at is not null) then raise exception 'New cast autoapproved';end if;
 update families set production_enabled=false where id=fid;
 insert into reference_photos(family_id,person_id,object_path,position) values(fid,pid,fid||'/ref.png',0);
 if (select production_enabled from families where id=fid) then raise exception 'Explicit pause overridden';end if;
 update families set production_enabled=true where id=fid;
 update people set memorial=true where id=pid;
 if (select production_enabled from families where id=fid) then raise exception 'Memorial transition kept living scenes active';end if;
 update families set production_enabled=true where id=fid;
 delete from people where id=pid;
 if (select production_enabled from families where id=fid) then raise exception 'Removed person still active';end if;
end$$;
select 'PASS: previous approved cast continues, pinned claim, no autoapproval, explicit pause and removal/memorial safeguards' result;
rollback;
