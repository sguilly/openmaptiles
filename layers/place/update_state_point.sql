DROP TRIGGER IF EXISTS trigger_update_point ON osm_state_point;

ALTER TABLE osm_state_point
    DROP CONSTRAINT IF EXISTS osm_state_point_rank_constraint;

-- etldoc: ne_10m_admin_1_states_provinces   -> osm_state_point
-- etldoc: osm_state_point                       -> osm_state_point

CREATE OR REPLACE FUNCTION update_osm_state_point(new_osm_id bigint) RETURNS void AS
$$
BEGIN

    WITH important_state_point AS (
        SELECT osm.geometry,
               osm.osm_id,
               osm.name,
               COALESCE(NULLIF(osm.name_en, ''), ne.name) AS name_en,
               ne.scalerank,
               ne.labelrank,
               ne.datarank
        FROM ne_10m_admin_1_states_provinces AS ne,
             osm_state_point AS osm
        WHERE
          -- We only match whether the point is within the Natural Earth polygon
          -- because name matching is difficult
            ST_Within(osm.geometry, ne.geometry)
          -- We leave out leess important states
          AND ne.scalerank <= 3
          AND ne.labelrank <= 2
    )
    UPDATE osm_state_point AS osm
        -- Normalize both scalerank and labelrank into a ranking system from 1 to 6.
    SET "rank" = LEAST(6, CEILING((scalerank + labelrank + datarank) / 3.0))
    FROM important_state_point AS ne
    WHERE (new_osm_id IS NULL OR osm.osm_id = new_osm_id) AND
          osm.osm_id = ne.osm_id;

    -- TODO: This shouldn't be necessary? The rank function makes something wrong...
    UPDATE osm_state_point AS osm
    SET "rank" = 1
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          "rank" = 0;

    DELETE FROM osm_state_point
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          "rank" IS NULL;

    UPDATE osm_state_point
    SET tags = update_tags(tags, geometry)
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          COALESCE(tags->'name:latin', tags->'name:nonlatin', tags->'name_int') IS NULL;

END;
$$ LANGUAGE plpgsql;

SELECT update_osm_state_point(NULL);

-- ALTER TABLE osm_state_point ADD CONSTRAINT osm_state_point_rank_constraint CHECK("rank" BETWEEN 1 AND 6);
CREATE INDEX IF NOT EXISTS osm_state_point_rank_idx ON osm_state_point ("rank");

-- Handle updates

CREATE SCHEMA IF NOT EXISTS place_state;

CREATE OR REPLACE FUNCTION place_state.update() RETURNS trigger AS
$$
BEGIN
    PERFORM update_osm_state_point(NEW.osm_id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trigger_update_point
    AFTER INSERT OR UPDATE
    ON osm_state_point
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE place_state.update();
