--retry
BEGIN;

--CREATE TABLE users (
--    id VARCHAR(255) PRIMARY KEY,  -- Using VARCHAR as primary key
--    password TEXT NOT NULL
--);

INSERT INTO public.users (id, password) VALUES ('john_doe', 'securepassword123');

COMMIT;
--MSSDATABASE=postgres