DROP TRIGGER IF EXISTS trigger_update_polygon ON osm_poi_polygon;

-- etldoc:  osm_poi_polygon ->  osm_poi_polygon

CREATE OR REPLACE FUNCTION update_poi_polygon(rec osm_poi_polygon) RETURNS osm_poi_polygon AS
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

    IF rec.station = 'subway' AND rec.subclass = 'station' THEN
        rec.subclass = 'subway';
    END IF;

    IF rec.funicular = 'yes' AND rec.subclass = 'station' THEN
        rec.subclass = 'halt';
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
    orig osm_poi_polygon;
    up osm_poi_polygon;
BEGIN
    FOR orig IN SELECT * FROM osm_poi_polygon
    LOOP
        up := update_poi_polygon(orig);
        IF orig.* IS DISTINCT FROM up.* THEN
            DELETE FROM osm_poi_polygon WHERE osm_poi_polygon.id = up.id;
            INSERT INTO osm_poi_polygon VALUES (up.*);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Handle updates

CREATE SCHEMA IF NOT EXISTS poi_polygon;

CREATE OR REPLACE FUNCTION poi_polygon.update() RETURNS trigger AS
$$
BEGIN
    RETURN update_poi_polygon(NEW);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_polygon
    BEFORE INSERT OR UPDATE
    ON osm_poi_polygon
    FOR EACH ROW
EXECUTE PROCEDURE poi_polygon.update();
