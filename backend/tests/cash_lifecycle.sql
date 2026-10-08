-- Run only in an isolated test DB. All fixture rows roll back.
begin;
do $$
declare c uuid; p uuid; t uuid; staff uuid:=gen_random_uuid(); o jsonb; again jsonb; total bigint;
begin
 insert into public.categories(name,slug) values ('TEST','test-'||staff) returning id into c;
 insert into public.products(category_id,name,slug,price) values(c,'TEST','test-'||staff,22000) returning id into p;
 insert into public.tables(number,qr_token) values(99999,'test-'||staff) returning id into t;
 insert into public.profiles(id,full_name,role) values(staff,'TEST','cashier');
 o:=tkm.checkout('test-key-'||staff,'test-access-token-'||staff,jsonb_build_object('table_token','test-'||staff,'payment_method','cash','items',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',2,'variant_ids','[]'::jsonb,'addon_ids','[]'::jsonb))));
 if o->>'status'<>'pending' or o->>'payment_status'<>'unpaid' then raise exception 'bad initial status';end if;
 if (o->>'total')::bigint<>44000 then raise exception 'bad total';end if;
 again:=tkm.checkout('test-key-'||staff,'test-access-token-'||staff,jsonb_build_object('table_token','test-'||staff,'payment_method','cash','items',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',2,'variant_ids','[]'::jsonb,'addon_ids','[]'::jsonb))));
 if again->>'id'<>o->>'id' then raise exception 'duplicate order';end if;
 begin perform tkm.complete_order((o->>'id')::uuid,staff);raise exception 'accepted unpaid completion';exception when check_violation then null;end;
 perform tkm.review_order((o->>'id')::uuid,staff,1,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',2,'variant_ids','[]'::jsonb,'addon_ids','[]'::jsonb)));
 begin perform tkm.confirm_cash((o->>'id')::uuid,staff,1,2);raise exception 'accepted insufficient cash';exception when check_violation then null;end;
 again:=tkm.confirm_cash((o->>'id')::uuid,staff,50000,2);
 if again->>'status'<>'confirmed' or again->>'payment_status'<>'paid' then raise exception 'payment not atomic';end if;
 if (again->>'change_rp')::bigint<>6000 then raise exception 'bad change';end if;
 perform tkm.confirm_cash((o->>'id')::uuid,staff,50000,2);
 if (select count(*) from public.payments where order_id=(o->>'id')::uuid)<>1 then raise exception 'duplicate payment';end if;
 again:=tkm.complete_order((o->>'id')::uuid,staff);
 if again->>'status'<>'completed' then raise exception 'not completed';end if;
 perform tkm.complete_order((o->>'id')::uuid,staff);
 if (select count(*) from public.order_status_history where order_id=(o->>'id')::uuid)<>3 then raise exception 'duplicate history';end if;
 if (select count(*) from tkm.outbox_events where order_id=(o->>'id')::uuid)<>4 then raise exception 'bad outbox';end if;
 raise notice 'PASS cash lifecycle, retry, payment gate, total/change, history/outbox';
end $$;
rollback;
