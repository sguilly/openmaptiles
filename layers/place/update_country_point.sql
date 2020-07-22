DROP TRIGGER IF EXISTS trigger_update_point ON osm_country_point;

-- etldoc: ne_10m_admin_0_countries   -> osm_country_point
-- etldoc: osm_country_point          -> osm_country_point

CREATE OR REPLACE FUNCTION update_osm_country_point(rec osm_country_point) RETURNS osm_country_point AS
$$
BEGIN
    rec.rank = 7;
    rec.iso3166_1_alpha_2 = COALESCE(
        NULLIF(rec.country_code_iso3166_1_alpha_2, ''),
        NULLIF(rec.iso3166_1_alpha_2, ''),
        NULLIF(rec.iso3166_1, '')
    );

    rec.rank = COALESCE((
            -- Normalize both scalerank and labelrank into a ranking system from 1 to 6
            -- where the ranks are still distributed uniform enough across all countries
            SELECT LEAST(6, CEILING((ne.scalerank + ne.labelrank) / 2.0))
            FROM ne_10m_admin_0_countries AS ne
            WHERE
                -- We match only countries with ISO codes to eliminate disputed countries
                iso3166_1_alpha_2 IS NOT NULL
                -- that lies inside polygon of sovereign country
                AND ST_Within(rec.geometry, ne.geometry)
        ), (
            -- Repeat the step for archipelago countries like Philippines or Indonesia
            -- whose label point is not within country's polygon
            SELECT LEAST(6, CEILING((ne.scalerank + ne.labelrank) / 2.0))
            FROM ne_10m_admin_0_countries AS ne
            WHERE
                ne.iso3166_1_alpha_2 IS NOT NULL
                AND NOT (rec."rank" BETWEEN 1 AND 6)
            ORDER BY ST_Distance(rec.geometry, ne.geometry)
            LIMIT 1
        ),
        6
    );

    -- TODO: This shouldn't be necessary? The rank function makes something wrong...
    IF rec.rank = 0 THEN
        rec.rank = 1;
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
    orig osm_country_point;
    up osm_country_point;
BEGIN
    FOR orig IN SELECT * FROM osm_country_point
    LOOP
        up := update_osm_country_point(orig);
        IF orig.* IS DISTINCT FROM up.* THEN
            DELETE FROM osm_country_point WHERE osm_country_point.id = up.id;
            INSERT INTO osm_country_point VALUES (up.*);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE INDEX IF NOT EXISTS osm_country_point_rank_idx ON osm_country_point ("rank");

-- Handle updates

CREATE SCHEMA IF NOT EXISTS place_country;

CREATE OR REPLACE FUNCTION place_country.update() RETURNS trigger AS
$$
BEGIN
    RETURN update_osm_country_point(NEW);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_point
    BEFORE INSERT OR UPDATE
    ON osm_country_point
    FOR EACH ROW
EXECUTE PROCEDURE place_country.update();
