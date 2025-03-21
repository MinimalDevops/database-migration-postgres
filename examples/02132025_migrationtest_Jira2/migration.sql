--retry
BEGIN;

INSERT INTO public.users (id, password) VALUES ('Abrahim', 'secpass321');

COMMIT;
--MSSDATABASE=postgres