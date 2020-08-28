DROP TRIGGER IF EXISTS trigger_osm_building_relation_store ON osm_building_relation;
DROP TRIGGER IF EXISTS trigger_osm_building_polygon_store ON osm_building_polygon;
DROP TRIGGER IF EXISTS trigger_flag ON building_polygon.buildings;
DROP TRIGGER IF EXISTS trigger_refresh ON building_polygon.updates;

-- etldoc: layer_building[shape=record fillcolor=lightpink, style="rounded,filled",
-- etldoc:     label="layer_building | <z13> z13 | <z14_> z14+ " ] ;

CREATE INDEX IF NOT EXISTS osm_building_relation_building_idx ON osm_building_relation (building) WHERE building = '' AND ST_GeometryType(geometry) = 'ST_Polygon';
CREATE INDEX IF NOT EXISTS osm_building_relation_member_idx ON osm_building_relation (member) WHERE role = 'outline';

-- Replace the index of imposm by a custom index
DROP INDEX IF EXISTS osm_building_polygon_geom;
CREATE INDEX IF NOT EXISTS osm_building_polygon_idx ON osm_building_polygon USING gist (geometry) WHERE ST_GeometryType(geometry) IN ('ST_Polygon', 'ST_MultiPolygon');

CREATE OR REPLACE VIEW osm_buildings_relation AS
    -- etldoc: osm_building_relation -> layer_building:z14_
    -- Buildings built from relations
SELECT
    member AS osm_id,
    geometry,
    COALESCE(CleanNumeric(height), CleanNumeric(buildingheight)) AS height,
    COALESCE(CleanNumeric(min_height), CleanNumeric(buildingmin_height)) AS min_height,
    COALESCE(CleanNumeric(levels), CleanNumeric(buildinglevels)) AS levels,
    COALESCE(CleanNumeric(min_level), CleanNumeric(buildingmin_level)) AS min_level,
    nullif(material, '') AS material,
    nullif(colour, '') AS colour,
    FALSE AS hide_3d
FROM osm_building_relation
WHERE building = ''
  AND ST_GeometryType(geometry) = 'ST_Polygon'
;

CREATE OR REPLACE VIEW osm_buildings_standalone AS
    -- etldoc: osm_building_polygon -> layer_building:z14_
    -- Standalone buildings
SELECT
    obp.osm_id,
    obp.geometry,
    COALESCE(CleanNumeric(obp.height), CleanNumeric(obp.buildingheight)) AS height,
    COALESCE(CleanNumeric(obp.min_height), CleanNumeric(obp.buildingmin_height)) AS min_height,
    COALESCE(CleanNumeric(obp.levels), CleanNumeric(obp.buildinglevels)) AS levels,
    COALESCE(CleanNumeric(obp.min_level), CleanNumeric(obp.buildingmin_level)) AS min_level,
    nullif(obp.material, '') AS material,
    nullif(obp.colour, '') AS colour,
    obr.role IS NOT NULL AS hide_3d
FROM osm_building_polygon obp
         LEFT JOIN osm_building_relation obr ON
        obp.osm_id >= 0 AND
        obr.member = obp.osm_id AND
        obr.role = 'outline'
WHERE ST_GeometryType(obp.geometry) IN ('ST_Polygon', 'ST_MultiPolygon')
;

CREATE OR REPLACE VIEW osm_all_buildings AS
SELECT *
FROM osm_buildings_relation
UNION ALL
SELECT *
FROM osm_buildings_standalone
;

DROP TABLE IF EXISTS osm_all_buildings_mat CASCADE;
CREATE TABLE osm_all_buildings_mat AS (
    SELECT
        array_agg(osm_id ORDER BY osm_id)    AS osm_ids,
        ST_Collect(geometry ORDER BY osm_id) AS geometry,
        height,
        min_height,
        levels,
        min_level,
        material,
        colour,
        hide_3d
    FROM (SELECT DISTINCT ON (osm_id) * FROM osm_all_buildings) AS t
    GROUP BY
        -- Cluster by windows to lower time and memory required.
        -- 100: scale of a building block at 45° of latitude, optimized on Paris area.
        (ST_XMin(geometry) / 100)::int,
        (ST_YMin(geometry) / 100)::int,
        height, min_height, levels, min_level, material, colour, hide_3d
);

CREATE INDEX osm_all_buildings_mat_geom ON osm_all_buildings_mat USING gist (geometry);

CREATE OR REPLACE FUNCTION layer_building(bbox geometry, zoom_level int)
    RETURNS TABLE
            (
                geometry          geometry,
                osm_id            bigint,
                render_height     int,
                render_min_height int,
                colour            text,
                hide_3d           boolean
            )
AS
$$
SELECT geometry,
       osm_id,
       render_height,
       render_min_height,
       COALESCE(colour, CASE material
           -- Ordered by count from taginfo
                            WHEN 'cement_block' THEN '#6a7880'
                            WHEN 'brick' THEN '#bd8161'
                            WHEN 'plaster' THEN '#dadbdb'
                            WHEN 'wood' THEN '#d48741'
                            WHEN 'concrete' THEN '#d3c2b0'
                            WHEN 'metal' THEN '#b7b1a6'
                            WHEN 'stone' THEN '#b4a995'
                            WHEN 'mud' THEN '#9d8b75'
                            WHEN 'steel' THEN '#b7b1a6' -- same as metal
                            WHEN 'glass' THEN '#5a81a0'
                            WHEN 'traditional' THEN '#bd8161' -- same as brick
                            WHEN 'masonry' THEN '#bd8161' -- same as brick
                            WHEN 'Brick' THEN '#bd8161' -- same as brick
                            WHEN 'tin' THEN '#b7b1a6' -- same as metal
                            WHEN 'timber_framing' THEN '#b3b0a9'
                            WHEN 'sandstone' THEN '#b4a995' -- same as stone
                            WHEN 'clay' THEN '#9d8b75' -- same as mud
           END) AS colour,
       CASE WHEN hide_3d THEN TRUE END AS hide_3d
FROM (
         SELECT
             -- etldoc: osm_building_block_gen1 -> layer_building:z13
             osm_id,
             geometry,
             NULL::int AS render_height,
             NULL::int AS render_min_height,
             NULL::text AS material,
             NULL::text AS colour,
             FALSE AS hide_3d
         FROM osm_building_block_gen1
         WHERE zoom_level = 13
           AND geometry && bbox
         UNION ALL
         SELECT
                                  -- etldoc: osm_building_polygon -> layer_building:z14_
            --DISTINCT ON (osm_id)
                                  osm_id,
                                  geometry,
                                  ceil(COALESCE(height, levels * 3.66, 5))::int AS render_height,
                                  floor(COALESCE(min_height, min_level * 3.66, 0))::int AS render_min_height,
                                  material,
                                  colour,
                                  hide_3d
         FROM (SELECT unnest(osm_ids) AS osm_id,
                      (ST_Dump(geometry)).geom AS geometry, -- Set Returning Functions are dumped in parallel
                      height,
                      min_height,
                      levels,
                      min_level,
                      material,
                      colour,
                      hide_3d
               FROM osm_all_buildings_mat
               WHERE geometry && bbox) AS t
         WHERE (levels IS NULL OR levels < 1000)
           AND (min_level IS NULL OR min_level < 1000)
           AND (height IS NULL OR height < 3000)
           AND (min_height IS NULL OR min_height < 3000)
           AND zoom_level >= 14
           AND geometry && bbox
     ) AS zoom_levels
ORDER BY render_height ASC, ST_YMin(geometry) DESC;
$$ LANGUAGE SQL STABLE
                -- STRICT
                PARALLEL SAFE
                ;

-- not handled: where a building outline covers building parts

-- Handle updates
CREATE SCHEMA IF NOT EXISTS building_polygon;

CREATE TABLE IF NOT EXISTS building_polygon.buildings
(
    id           serial PRIMARY KEY,
    osm_id       bigint,
    old_geometry geometry(Geometry, 3857),
    new_geometry geometry(Geometry, 3857)
);
CREATE OR REPLACE FUNCTION building_polygon.store() RETURNS trigger AS
$$
BEGIN
    IF (tg_op = 'DELETE') THEN
        IF ST_GeometryType(OLD.geometry) IN ('ST_Polygon', 'ST_MultiPolygon') THEN
            INSERT INTO building_polygon.buildings(osm_id, old_geometry, new_geometry)
            VALUES (OLD.osm_id, OLD.geometry, NULL::geometry);
        END IF;
    ELSIF (tg_op = 'UPDATE') THEN
        IF ST_GeometryType(OLD.geometry) IN ('ST_Polygon', 'ST_MultiPolygon') OR ST_GeometryType(NEW.geometry) IN ('ST_Polygon', 'ST_MultiPolygon') THEN
            INSERT INTO building_polygon.buildings(osm_id, old_geometry, new_geometry)
            VALUES (NEW.osm_id,
                    CASE WHEN ST_GeometryType(OLD.geometry) IN ('ST_Polygon', 'ST_MultiPolygon') THEN OLD.geometry END,
                    CASE WHEN ST_GeometryType(NEW.geometry) IN ('ST_Polygon', 'ST_MultiPolygon') THEN NEW.geometry END);
        END IF;
    ELSIF (tg_op = 'INSERT') THEN
        IF ST_GeometryType(NEW.geometry) IN ('ST_Polygon', 'ST_MultiPolygon') THEN
            INSERT INTO building_polygon.buildings(osm_id, old_geometry, new_geometry)
            VALUES (NEW.osm_id, NULL::geometry, NEW.geometry);
        END IF;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS building_polygon.updates
(
    id serial PRIMARY KEY,
    t  text,
    UNIQUE (t)
);
CREATE OR REPLACE FUNCTION building_polygon.flag() RETURNS trigger AS
$$
BEGIN
    INSERT INTO building_polygon.updates(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION building_polygon.refresh() RETURNS trigger AS
$$
BEGIN
    RAISE LOG 'Update osm_all_buildings_mat';

    -- Compact the change history to keep only the first and last version
    CREATE TEMP TABLE old_new_buildings AS
    SELECT DISTINCT ON (osm_id) osm_id,
                                old_geometry,
                                new_geometry
    FROM (
             SELECT osm_id,
                    first_value(old_geometry) OVER (PARTITION BY osm_id ORDER BY id) AS old_geometry,
                    last_value(new_geometry) OVER (PARTITION BY osm_id ORDER BY id)  AS new_geometry
             FROM building_polygon.buildings
         ) AS t;

    -- Flatten old and new version of building
    CREATE TEMP VIEW touched_buildings AS
    SELECT DISTINCT(osm_id) osm_id, geometry
    FROM (SELECT osm_id, unnest(ARRAY [old_geometry, new_geometry]) AS geometry FROM old_new_buildings) AS t
    WHERE geometry IS NOT NULL;

    -- Seach for clusters of changed buildings
    CREATE TEMP TABLE impacted_clusters AS
    SELECT osm_ids,
           osm_all_buildings_mat.geometry,
           height,
           min_height,
           levels,
           min_level,
           material,
           colour,
           hide_3d
    FROM osm_all_buildings_mat
             JOIN touched_buildings ON
        touched_buildings.geometry && osm_all_buildings_mat.geometry AND
        touched_buildings.osm_id = ANY(osm_all_buildings_mat.osm_ids);

    -- Remove old version of impacted clusters
    DELETE
    FROM osm_all_buildings_mat
        USING impacted_clusters
    WHERE osm_all_buildings_mat.geometry && impacted_clusters.geometry AND
          impacted_clusters.osm_ids && osm_all_buildings_mat.osm_ids;

    CREATE TEMP TABLE old_buildings AS
    SELECT osm_id FROM old_new_buildings WHERE old_geometry IS NOT NULL;
    CREATE INDEX old_buildings_osm_id_idx ON old_buildings(osm_id);
    CREATE TEMP VIEW new_buildings AS
    SELECT osm_id FROM old_new_buildings WHERE new_geometry IS NOT NULL;

    -- Get new version of buildings with full attributes
    CREATE TEMP VIEW new_buildings_full AS
    SELECT osm_buildings.*
    FROM new_buildings
             JOIN osm_buildings_relation AS osm_buildings ON
            osm_buildings.osm_id = new_buildings.osm_id
    UNION ALL
    SELECT osm_buildings.*
    FROM new_buildings
             JOIN osm_buildings_standalone AS osm_buildings ON
            osm_buildings.osm_id = new_buildings.osm_id;

    -- Unpack impacted clusters
    CREATE TEMP VIEW unclustered_buildings AS
    SELECT unnest(osm_ids) AS osm_id,
           (ST_Dump(geometry)).geom AS geometry, -- Set Returning Functions are dumped in parallel
           height,
           min_height,
           levels,
           min_level,
           material,
           colour,
           hide_3d
    FROM impacted_clusters;

    -- Discart old buildings from clusters
    CREATE TEMP VIEW untouched_buildings AS
    SELECT unclustered_buildings.osm_id,
           unclustered_buildings.geometry,
           height,
           min_height,
           levels,
           min_level,
           material,
           colour,
           hide_3d
    FROM unclustered_buildings
             LEFT JOIN old_buildings ON
            old_buildings.osm_id = unclustered_buildings.osm_id
    WHERE old_buildings.osm_id IS NULL;

    -- Reassemble previous untouched buildings and new buildings
    CREATE TEMP VIEW current_buildings AS
    SELECT *
    FROM untouched_buildings
    UNION
    SELECT osm_id,
           geometry,
           height,
           min_height,
           levels,
           min_level,
           material,
           colour,
           hide_3d
    FROM new_buildings_full;

    -- Build and save new clusters
    INSERT INTO osm_all_buildings_mat
    SELECT array_agg(osm_id ORDER BY osm_id) AS osm_ids,
           ST_Collect(geometry ORDER BY osm_id) AS geometry,
           height,
           min_height,
           levels,
           min_level,
           material,
           colour,
           hide_3d
    FROM current_buildings AS t
    GROUP BY
        -- Cluster by windows to lower time and memory required
        (ST_XMin(geometry) / 100)::int,
        (ST_YMin(geometry) / 100)::int,
        height, min_height, levels, min_level, material, colour, hide_3d;

    DELETE FROM building_polygon.buildings;
    DELETE FROM building_polygon.updates;
    DROP TABLE old_new_buildings CASCADE;
    DROP TABLE impacted_clusters CASCADE;
    DROP TABLE old_buildings CASCADE;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_osm_building_relation_store
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_building_relation
    FOR EACH ROW
EXECUTE PROCEDURE building_polygon.store();

CREATE TRIGGER trigger_osm_building_polygon_store
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_building_polygon
    FOR EACH ROW
EXECUTE PROCEDURE building_polygon.store();

CREATE TRIGGER trigger_flag
    AFTER INSERT
    ON building_polygon.buildings
    FOR EACH STATEMENT
EXECUTE PROCEDURE building_polygon.flag();

CREATE CONSTRAINT TRIGGER trigger_refresh
    AFTER INSERT
    ON building_polygon.updates
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE building_polygon.refresh();
