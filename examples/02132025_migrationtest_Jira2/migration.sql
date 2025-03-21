--retry
BEGIN;

INSERT INTO public.users (id, password) VALUES ('tapi', 'securepassword123');

COMMIT;
--MSSDATABASE=postgres