DROP TRIGGER IF EXISTS trigger_update_polygon ON osm_island_polygon;

-- etldoc:  osm_island_polygon ->  osm_island_polygon
CREATE OR REPLACE FUNCTION update_osm_island_polygon(new_osm_id bigint) RETURNS void AS
$$
BEGIN
    UPDATE osm_island_polygon
    SET geometry = ST_PointOnSurface(geometry)
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          ST_GeometryType(geometry) <> 'ST_Point';

    UPDATE osm_island_polygon
    SET tags = update_tags(tags, geometry)
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          COALESCE(tags->'name:latin', tags->'name:nonlatin', tags->'name_int') IS NULL;

END;
$$ LANGUAGE plpgsql;

SELECT update_osm_island_polygon(NULL);

ANALYZE osm_island_polygon;

-- Handle updates

CREATE SCHEMA IF NOT EXISTS place_island_polygon;

CREATE OR REPLACE FUNCTION place_island_polygon.update() RETURNS trigger AS
$$
BEGIN
    PERFORM update_osm_island_polygon(NEW.osm_id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trigger_update_polygon
    AFTER INSERT OR UPDATE
    ON osm_island_polygon
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE place_island_polygon.update();
