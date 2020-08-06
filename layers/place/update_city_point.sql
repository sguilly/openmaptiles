DROP TRIGGER IF EXISTS trigger_ipdate_point ON osm_city_point;

CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE OR REPLACE FUNCTION update_osm_city_point(new_osm_id bigint) RETURNS void AS
$$
BEGIN

    -- Clear  OSM key:rank ( https://github.com/openmaptiles/openmaptiles/issues/108 )
    -- etldoc: osm_city_point          -> osm_city_point
    UPDATE osm_city_point
    SET "rank" = NULL
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          "rank" IS NOT NULL;

    -- etldoc: ne_10m_populated_places -> osm_city_point
    -- etldoc: osm_city_point          -> osm_city_point

    WITH important_city_point AS (
        SELECT osm.geometry, osm.osm_id, osm.name, osm.name_en, ne.scalerank, ne.labelrank
        FROM ne_10m_populated_places AS ne,
             osm_city_point AS osm
        WHERE (
                (osm.tags ? 'wikidata' AND osm.tags->'wikidata' = ne.wikidataid) OR
                lower(osm.name) IN (lower(ne.name), lower(ne.namealt), lower(ne.meganame), lower(ne.gn_ascii), lower(ne.nameascii)) OR
                lower(osm.name_en) IN (lower(ne.name), lower(ne.namealt), lower(ne.meganame), lower(ne.gn_ascii), lower(ne.nameascii)) OR
                ne.name = unaccent(osm.name)
            )
          AND osm.place IN ('city', 'town', 'village')
          AND ST_DWithin(ne.geometry, osm.geometry, 50000)
    )
    UPDATE osm_city_point AS osm
        -- Move scalerank to range 1 to 10 and merge scalerank 5 with 6 since not enough cities
        -- are in the scalerank 5 bucket
    SET "rank" = CASE WHEN scalerank <= 5 THEN scalerank + 1 ELSE scalerank END
    FROM important_city_point AS ne
    WHERE (new_osm_id IS NULL OR osm.osm_id = new_osm_id) AND
          osm.osm_id = ne.osm_id;

    UPDATE osm_city_point
    SET tags = update_tags(tags, geometry)
    WHERE (new_osm_id IS NULL OR osm_id = new_osm_id) AND
          COALESCE(tags->'name:latin', tags->'name:nonlatin', tags->'name_int') IS NULL;

END;
$$ LANGUAGE plpgsql;

SELECT update_osm_city_point(NULL);

CREATE INDEX IF NOT EXISTS osm_city_point_rank_idx ON osm_city_point ("rank");

-- Handle updates

CREATE SCHEMA IF NOT EXISTS place_city;

CREATE OR REPLACE FUNCTION place_city.update() RETURNS trigger AS
$$
BEGIN
    PERFORM update_osm_city_point(NEW.osm_id);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trigger_update_point
    AFTER INSERT OR UPDATE
    ON osm_city_point
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE place_city.update();
