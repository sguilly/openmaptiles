DROP TRIGGER IF EXISTS trigger_update_point ON osm_aerodrome_label_point;

-- etldoc: osm_aerodrome_label_point -> osm_aerodrome_label_point
CREATE OR REPLACE FUNCTION update_aerodrome_label_point(new_osm_id bigint) RETURNS void AS
$$
BEGIN
    UPDATE osm_aerodrome_label_point
    SET geometry = ST_Centroid(geometry)
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          ST_GeometryType(geometry) <> 'ST_Point';

    UPDATE osm_aerodrome_label_point
    SET tags = update_tags(tags, geometry)
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          COALESCE(tags->'name:latin', tags->'name:nonlatin', tags->'name_int') IS NULL;
END;
$$ LANGUAGE plpgsql;

SELECT update_aerodrome_label_point(NULL);

-- Handle updates

CREATE SCHEMA IF NOT EXISTS aerodrome_label;

CREATE OR REPLACE FUNCTION aerodrome_label.update() RETURNS trigger AS
$$
BEGIN
    PERFORM update_osm_peak_point(NEW.osm_id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trigger_update_point
    AFTER INSERT OR UPDATE
    ON osm_aerodrome_label_point
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE aerodrome_label.update();
