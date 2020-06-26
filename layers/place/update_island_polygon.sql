DROP TRIGGER IF EXISTS trigger_update_polygon ON osm_island_polygon;

-- etldoc:  osm_island_polygon ->  osm_island_polygon
CREATE OR REPLACE FUNCTION update_osm_island_polygon(rec osm_island_polygon) RETURNS osm_island_polygon AS
$$
BEGIN
    IF ST_GeometryType(rec.geometry) <> 'ST_Point' THEN
        rec.geometry = ST_PointOnSurface(rec.geometry);
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
    orig osm_island_polygon;
    up osm_island_polygon;
BEGIN
    FOR orig IN SELECT * FROM osm_island_polygon
    LOOP
        up := update_osm_island_polygon(orig);
        IF orig.* IS DISTINCT FROM up.* THEN
            DELETE FROM osm_island_polygon WHERE osm_island_polygon.id = up.id;
            INSERT INTO osm_island_polygon VALUES (up.*);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Handle updates

CREATE SCHEMA IF NOT EXISTS place_island_polygon;

CREATE OR REPLACE FUNCTION place_island_polygon.update() RETURNS trigger AS
$$
BEGIN
    RETURN update_osm_island_polygon(NEW);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_polygon
    BEFORE INSERT OR UPDATE
    ON osm_island_polygon
    FOR EACH ROW
EXECUTE PROCEDURE place_island_polygon.update();
