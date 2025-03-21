--skip
BEGIN;

INSERT INTO public.users (id, password) VALUES ('john_doe', 'secpass321');

COMMIT;
--MSSDATABASE=postgres