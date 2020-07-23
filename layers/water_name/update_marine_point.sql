DROP TRIGGER IF EXISTS trigger_update ON osm_marine_point;

CREATE OR REPLACE FUNCTION update_osm_marine_point(rec osm_marine_point) RETURNS osm_marine_point AS
$$
BEGIN
    -- etldoc: ne_10m_geography_marine_polys -> osm_marine_point
    -- etldoc: osm_marine_point              -> osm_marine_point
    rec.rank = (
        SELECT scalerank
        FROM ne_10m_geography_marine_polys AS ne
        WHERE trim(regexp_replace(ne.name, '\\s+', ' ', 'g')) ILIKE rec.name
           OR trim(regexp_replace(ne.name, '\\s+', ' ', 'g')) ILIKE rec.tags->'name:en'
           OR trim(regexp_replace(ne.name, '\\s+', ' ', 'g')) ILIKE rec.tags->'name:es'
           OR rec.name ILIKE trim(regexp_replace(ne.name, '\\s+', ' ', 'g')) || ' %'
    );

    IF COALESCE(rec.tags->'name:latin', rec.tags->'name:nonlatin', rec.tags->'name_int') IS NULL THEN
        rec.tags = update_tags(rec.tags, rec.geometry);
    END IF;

    RETURN rec;
END;
$$ LANGUAGE plpgsql;

DO
$$
DECLARE
    orig osm_marine_point;
    up osm_marine_point;
BEGIN
    FOR orig IN SELECT * FROM osm_marine_point
    LOOP
        up := update_osm_marine_point(orig);
        IF orig.* IS DISTINCT FROM up.* THEN
            DELETE FROM osm_marine_point WHERE osm_marine_point.id = up.id;
            INSERT INTO osm_marine_point VALUES (up.*);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE INDEX IF NOT EXISTS osm_marine_point_rank_idx ON osm_marine_point ("rank");

-- Handle updates
CREATE SCHEMA IF NOT EXISTS water_name_marine;

CREATE OR REPLACE FUNCTION water_name_marine.update() RETURNS trigger AS
$$
BEGIN
    RETURN update_osm_marine_point(NEW);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update
    BEFORE INSERT OR UPDATE
    ON osm_marine_point
    FOR EACH ROW
EXECUTE PROCEDURE water_name_marine.update();
