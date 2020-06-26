DROP TRIGGER IF EXISTS trigger_update_point ON osm_city_point;

CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE OR REPLACE FUNCTION update_osm_city_point(rec osm_city_point) RETURNS osm_city_point AS
$$
BEGIN
    -- etldoc: ne_10m_populated_places -> osm_city_point
    -- etldoc: osm_city_point          -> osm_city_point
    rec.rank = (
        -- Move scalerank to range 1 to 10 and merge scalerank 5 with 6 since not enough cities
        -- are in the scalerank 5 bucket
        SELECT CASE WHEN scalerank <= 5 THEN scalerank + 1 ELSE scalerank END
        FROM ne_10m_populated_places AS ne
        WHERE
            (
                (rec.tags ? 'wikidata' AND rec.tags->'wikidata' = ne.wikidataid) OR
                ne.name ILIKE rec.name OR
                ne.name ILIKE rec.name_en OR
                ne.namealt ILIKE rec.name OR
                ne.namealt ILIKE rec.name_en OR
                ne.meganame ILIKE rec.name OR
                ne.meganame ILIKE rec.name_en OR
                ne.gn_ascii ILIKE rec.name OR
                ne.gn_ascii ILIKE rec.name_en OR
                ne.nameascii ILIKE rec.name OR
                ne.nameascii ILIKE rec.name_en OR
                ne.name = unaccent(rec.name)
            )
            AND rec.place IN ('city', 'town', 'village')
            AND ST_DWithin(ne.geometry, rec.geometry, 50000)
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
    orig osm_city_point;
    up osm_city_point;
BEGIN
    FOR orig IN SELECT * FROM osm_city_point
    LOOP
        up := update_osm_city_point(orig);
        IF orig.* IS DISTINCT FROM up.* THEN
            DELETE FROM osm_city_point WHERE osm_city_point.id = up.id;
            INSERT INTO osm_city_point VALUES (up.*);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE INDEX IF NOT EXISTS osm_city_point_rank_idx ON osm_city_point ("rank");

-- Handle updates

CREATE SCHEMA IF NOT EXISTS place_city;

CREATE OR REPLACE FUNCTION place_city.update() RETURNS trigger AS
$$
BEGIN
    RETURN update_osm_city_point(NEW);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_point
    BEFORE INSERT OR UPDATE
    ON osm_city_point
    FOR EACH ROW
EXECUTE PROCEDURE place_city.update();
