DROP TRIGGER IF EXISTS trigger_update_point ON osm_continent_point;

-- etldoc:  osm_continent_point ->  osm_continent_point
CREATE OR REPLACE FUNCTION update_osm_continent_point(new_osm_id bigint) RETURNS void AS
$$
BEGIN
    UPDATE osm_continent_point
    SET tags = update_tags(tags, geometry)
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          COALESCE(tags->'name:latin', tags->'name:nonlatin', tags->'name_int') IS NULL;

END;
$$ LANGUAGE plpgsql;

SELECT update_osm_continent_point(NULL);

-- Handle updates

CREATE SCHEMA IF NOT EXISTS place_continent_point;

CREATE OR REPLACE FUNCTION place_continent_point.update() RETURNS trigger AS
$$
BEGIN
    PERFORM update_osm_continent_point(NEW.osm_id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trigger_update_point
    AFTER INSERT OR UPDATE
    ON osm_continent_point
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE place_continent_point.update();
