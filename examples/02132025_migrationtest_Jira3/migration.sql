--retry
BEGIN;

--INSERT INTO public.users (id, password) VALUES ('tapi', 'securepassword123');
INSERT INTO public.users (id, password) VALUES ('mark_clark', 'securepassword123');

COMMIT;
--MSSDATABASE=postgres