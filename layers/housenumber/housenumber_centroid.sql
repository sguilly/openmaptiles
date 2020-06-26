DROP TRIGGER IF EXISTS trigger_update_point ON osm_housenumber_point;

-- etldoc: osm_housenumber_point -> osm_housenumber_point
CREATE OR REPLACE FUNCTION convert_housenumber_point(new_osm_id bigint) RETURNS void AS
$$
BEGIN
    UPDATE osm_housenumber_point
    SET geometry =
            CASE
                WHEN ST_NPoints(ST_ConvexHull(geometry)) = ST_NPoints(geometry)
                    THEN ST_Centroid(geometry)
                ELSE ST_PointOnSurface(geometry)
                END
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          ST_GeometryType(geometry) <> 'ST_Point';
END;
$$ LANGUAGE plpgsql;

SELECT convert_housenumber_point(NULL);

-- Handle updates

CREATE SCHEMA IF NOT EXISTS housenumber;

CREATE OR REPLACE FUNCTION housenumber.update() RETURNS trigger AS
$$
BEGIN
    PERFORM convert_housenumber_point(NEW.osm_id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trigger_update_point
    AFTER INSERT OR UPDATE
    ON osm_housenumber_point
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE housenumber.update();
