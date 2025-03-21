--retry
BEGIN;

INSERT INTO public.users (id, password) VALUES ('mark_clark', 'secpass321');

COMMIT;
--MSSDATABASE=postgres