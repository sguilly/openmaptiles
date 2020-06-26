DROP TRIGGER IF EXISTS trigger_update_point ON osm_island_point;

-- etldoc:  osm_island_point ->  osm_island_point
CREATE OR REPLACE FUNCTION update_osm_island_point(rec osm_island_point) RETURNS osm_island_point AS
$$
BEGIN
    IF COALESCE(rec.tags->'name:latin', rec.tags->'name:nonlatin', rec.tags->'name_int') IS NULL THEN
        rec.tags = update_tags(rec.tags, rec.geometry);
    END IF;

    RETURN rec;
END;
$$ LANGUAGE plpgsql;

DO
$$
DECLARE
    orig osm_island_point;
    up osm_island_point;
BEGIN
    FOR orig IN SELECT * FROM osm_island_point
    LOOP
        up := update_osm_island_point(orig);
        IF orig.* IS DISTINCT FROM up.* THEN
            DELETE FROM osm_island_point WHERE osm_island_point.id = up.id;
            INSERT INTO osm_island_point VALUES (up.*);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Handle updates

CREATE SCHEMA IF NOT EXISTS place_island_point;

CREATE OR REPLACE FUNCTION place_island_point.update() RETURNS trigger AS
$$
BEGIN
    RETURN update_osm_island_point(NEW);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_point
    BEFORE INSERT OR UPDATE
    ON osm_island_point
    FOR EACH ROW
EXECUTE PROCEDURE place_island_point.update();
