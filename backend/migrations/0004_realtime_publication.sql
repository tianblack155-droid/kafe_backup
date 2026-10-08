-- Single-instance local outbox publication marker only. Preserve event rows and
-- payload immutability; no table-wide UPDATE or additional catalog/profile ACLs.
grant update(published_at) on tkm.outbox_events to tkm_runtime;
