DROP TRIGGER IF EXISTS trigger_update_point ON osm_aerodrome_label_point;

-- etldoc: osm_aerodrome_label_point -> osm_aerodrome_label_point
CREATE OR REPLACE FUNCTION update_aerodrome_label_point(rec osm_aerodrome_label_point) RETURNS osm_aerodrome_label_point AS
$$
BEGIN
    IF ST_GeometryType(rec.geometry) <> 'ST_Point' THEN
        rec.geometry := ST_Centroid(rec.geometry);
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
    orig osm_aerodrome_label_point;
    up osm_aerodrome_label_point;
BEGIN
    FOR orig IN SELECT * FROM osm_aerodrome_label_point
    LOOP
        up := update_aerodrome_label_point(orig);
        IF orig.* IS DISTINCT FROM up.* THEN
            DELETE FROM osm_aerodrome_label_point WHERE osm_aerodrome_label_point.id = up.id;
            INSERT INTO osm_aerodrome_label_point VALUES (up.*);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Handle updates

CREATE SCHEMA IF NOT EXISTS aerodrome_label;

CREATE OR REPLACE FUNCTION aerodrome_label.update() RETURNS trigger AS
$$
BEGIN
    RETURN update_aerodrome_label_point(NEW);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_point
    BEFORE INSERT OR UPDATE
    ON osm_aerodrome_label_point
    FOR EACH ROW
EXECUTE PROCEDURE aerodrome_label.update();
