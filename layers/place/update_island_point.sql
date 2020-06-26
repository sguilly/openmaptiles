DROP TRIGGER IF EXISTS trigger_update_point ON osm_island_point;

-- etldoc:  osm_island_point ->  osm_island_point
CREATE OR REPLACE FUNCTION update_osm_island_point(new_osm_id bigint) RETURNS void AS
$$
BEGIN
    UPDATE osm_island_point
    SET tags = update_tags(tags, geometry)
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          COALESCE(tags->'name:latin', tags->'name:nonlatin', tags->'name_int') IS NULL;

END;
$$ LANGUAGE plpgsql;

SELECT update_osm_island_point(NULL);

-- Handle updates

CREATE SCHEMA IF NOT EXISTS place_island_point;

CREATE OR REPLACE FUNCTION place_island_point.update() RETURNS trigger AS
$$
BEGIN
    PERFORM update_osm_island_point(NEW.osm_id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trigger_update_point
    AFTER INSERT OR UPDATE
    ON osm_island_point
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE place_island_point.update();
