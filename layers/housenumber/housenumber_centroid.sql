DROP TRIGGER IF EXISTS trigger_update_point ON osm_housenumber_point;

-- etldoc: osm_housenumber_point -> osm_housenumber_point
CREATE OR REPLACE FUNCTION convert_housenumber_point(rec osm_housenumber_point) RETURNS osm_housenumber_point AS
$$
BEGIN
    IF ST_GeometryType(rec.geometry) <> 'ST_Point' THEN
        rec.geometry :=
            CASE
                WHEN ST_NPoints(ST_ConvexHull(rec.geometry)) = ST_NPoints(rec.geometry)
                    THEN ST_Centroid(rec.geometry)
                ELSE ST_PointOnSurface(rec.geometry)
                END;
    END IF;

    RETURN rec;
END;
$$ LANGUAGE plpgsql;

DO
$$
DECLARE
    orig osm_housenumber_point;
    up osm_housenumber_point;
BEGIN
    FOR orig IN SELECT * FROM osm_housenumber_point
    LOOP
        up := convert_housenumber_point(orig);
        IF orig.* IS DISTINCT FROM up.* THEN
            DELETE FROM osm_housenumber_point WHERE osm_housenumber_point.id = up.id;
            INSERT INTO osm_housenumber_point VALUES (up.*);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Handle updates

CREATE SCHEMA IF NOT EXISTS housenumber;

CREATE OR REPLACE FUNCTION housenumber.update() RETURNS trigger AS
$$
BEGIN
    RETURN convert_housenumber_point(NEW);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_point
    BEFORE INSERT OR UPDATE
    ON osm_housenumber_point
    FOR EACH ROW
EXECUTE PROCEDURE housenumber.update();
