DROP TRIGGER IF EXISTS trigger_update_point ON osm_peak_point;

-- etldoc:  osm_peak_point ->  osm_peak_point
CREATE OR REPLACE FUNCTION update_osm_peak_point(rec osm_peak_point) RETURNS osm_peak_point AS
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
    orig osm_peak_point;
    up osm_peak_point;
BEGIN
    FOR orig IN SELECT * FROM osm_peak_point
    LOOP
        up := update_osm_peak_point(orig);
        IF orig.* IS DISTINCT FROM up.* THEN
            DELETE FROM osm_peak_point WHERE osm_peak_point.id = up.id;
            INSERT INTO osm_peak_point VALUES (up.*);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Handle updates

CREATE SCHEMA IF NOT EXISTS mountain_peak_point;

CREATE OR REPLACE FUNCTION mountain_peak_point.update() RETURNS trigger AS
$$
BEGIN
    RETURN update_osm_peak_point(NEW);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_point
    BEFORE INSERT OR UPDATE
    ON osm_peak_point
    FOR EACH ROW
EXECUTE PROCEDURE mountain_peak_point.update();
