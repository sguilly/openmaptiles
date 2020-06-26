DROP TRIGGER IF EXISTS trigger_update_point ON osm_state_point;
DROP TRIGGER IF EXISTS trigger_delete_point ON osm_state_point;

-- etldoc: ne_10m_admin_1_states_provinces   -> osm_state_point
-- etldoc: osm_state_point                       -> osm_state_point

CREATE OR REPLACE FUNCTION update_osm_state_point(rec osm_state_point) RETURNS osm_state_point AS
$$
BEGIN
    rec.rank = (
        -- Normalize both scalerank and labelrank into a ranking system from 1 to 6.
        SELECT LEAST(6, CEILING((ne.scalerank + ne.labelrank + ne.datarank) / 3.0))
        FROM ne_10m_admin_1_states_provinces AS ne
        WHERE
            -- We only match whether the point is within the Natural Earth polygon
            -- because name matching is difficult
            ST_Within(rec.geometry, ne.geometry)
            -- We leave out leess important states
            AND ne.scalerank <= 3
            AND ne.labelrank <= 2
    );

    -- TODO: This shouldn't be necessary? The rank function makes something wrong...
    IF rec.rank = 0 THEN
        rec.rank = 1;
    END IF;

    IF COALESCE(rec.tags->'name:latin', rec.tags->'name:nonlatin', rec.tags->'name_int') IS NULL THEN
        rec.tags = update_tags(rec.tags, rec.geometry);
    END IF;

    RETURN rec;
END;
$$ LANGUAGE plpgsql;

DO
$$
DECLARE
    orig osm_state_point;
    up osm_state_point;
BEGIN
    FOR orig IN SELECT * FROM osm_state_point
    LOOP
        up := update_osm_state_point(orig);
        IF orig.* IS DISTINCT FROM up.* THEN
            DELETE FROM osm_state_point WHERE osm_state_point.id = up.id;
            INSERT INTO osm_state_point VALUES (up.*);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE INDEX IF NOT EXISTS osm_state_point_rank_idx ON osm_state_point ("rank");

DELETE FROM osm_state_point
WHERE rank IS NULL;

-- Handle updates

CREATE SCHEMA IF NOT EXISTS place_state;

CREATE OR REPLACE FUNCTION place_state.update() RETURNS trigger AS
$$
BEGIN
    RETURN update_osm_state_point(NEW);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION place_state.delete() RETURNS trigger AS
$$
BEGIN
    DELETE FROM osm_state_point
    WHERE rank IS NULL;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_point
    BEFORE INSERT OR UPDATE
    ON osm_state_point
    FOR EACH ROW
EXECUTE PROCEDURE place_state.update();

CREATE CONSTRAINT TRIGGER trigger_delete_point
    AFTER INSERT OR UPDATE
    ON osm_state_point
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE place_state.delete();
