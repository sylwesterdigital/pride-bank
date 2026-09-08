-- Pride-only schema ownership hardening.
-- The bootstrap verifies current_database() and database ownership before migrations.
ALTER SCHEMA public OWNER TO pride_owner;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM pride_app;
GRANT USAGE, CREATE ON SCHEMA public TO pride_owner;
GRANT USAGE ON SCHEMA public TO pride_app;
