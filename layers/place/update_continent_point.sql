DROP TRIGGER IF EXISTS trigger_update_point ON osm_continent_point;

-- etldoc:  osm_continent_point ->  osm_continent_point
CREATE OR REPLACE FUNCTION update_osm_continent_point(rec osm_continent_point) RETURNS osm_continent_point AS
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
    orig osm_continent_point;
    up osm_continent_point;
BEGIN
    FOR orig IN SELECT * FROM osm_continent_point
    LOOP
        up := update_osm_continent_point(orig);
        IF orig.* IS DISTINCT FROM up.* THEN
            DELETE FROM osm_continent_point WHERE osm_continent_point.id = up.id;
            INSERT INTO osm_continent_point VALUES (up.*);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Handle updates

CREATE SCHEMA IF NOT EXISTS place_continent_point;

CREATE OR REPLACE FUNCTION place_continent_point.update() RETURNS trigger AS
$$
BEGIN
    RETURN update_osm_continent_point(NEW);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_point
    BEFORE INSERT OR UPDATE
    ON osm_continent_point
    FOR EACH ROW
EXECUTE PROCEDURE place_continent_point.update();
