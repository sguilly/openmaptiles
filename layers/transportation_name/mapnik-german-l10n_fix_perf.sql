CREATE or REPLACE FUNCTION osml10n_contains_cyrillic(text) RETURNS BOOLEAN AS $$
  DECLARE
    i integer;
    c integer;
  BEGIN
    FOR i IN 1..char_length($1) LOOP
      c = ascii(substr($1, i, 1));
      IF ((c > x'0400'::int) AND (c < x'04FF'::int)) THEN
        RETURN true;
      END IF;
    END LOOP;
    RETURN false;
  END;
$$ LANGUAGE 'plpgsql' IMMUTABLE;


CREATE OR REPLACE FUNCTION osml10n_street_abbrev_all(longname text) RETURNS TEXT AS $$
 SELECT
  CASE WHEN osml10n_contains_cyrillic(longname) THEN
    osml10n_street_abbrev_non_latin(longname)
  ELSE
    osml10n_street_abbrev_latin(longname)
  END;
$$ LANGUAGE SQL IMMUTABLE;


CREATE OR REPLACE FUNCTION osml10n_street_abbrev_fr(longname text) RETURNS TEXT AS $$
 DECLARE
  match text[];
 BEGIN
  IF strpos(longname, 'Avenue') > 0 THEN
    /* These are also French names and Avenue is not at the beginning of the Name
      those apear in French speaking parts of canada
      + Normalize ^1ere, ^1re, ^1e to 1re */
    longname = regexp_replace(longname, '^1([eè]?r?)e Avenue\M','1re Av.');
    longname = regexp_replace(longname, '^([0-9]+)e Avenue\M','\1e Av.');
  END IF;

  match = regexp_matches(longname, '^(Avenue|Boulevard|Chemin|Esplanade|Impasse|Passage|Promenade|Route|Ruelle|Sentier)\M');
  IF match IS NOT NULL THEN
    longname = CASE match[1]
      /* We assume, that in French "Avenue" is always at the beginning of the name
          otherwise this is likely English. */
      WHEN 'Avenue' THEN 'Av.'
      WHEN 'Boulevard' THEN 'Bd'
      WHEN 'Chemin' THEN 'Ch.'
      WHEN 'Esplanade' THEN 'Espl.'
      WHEN 'Impasse' THEN 'Imp.'
      WHEN 'Passage' THEN 'Pass.'
      WHEN 'Promenade' THEN 'Prom.'
      WHEN 'Route' THEN 'Rte'
      WHEN 'Ruelle' THEN 'Rle'
      WHEN 'Sentier' THEN 'Sent.'
    END || substr(longname, length(match[1]) + 1);
  END IF;

  RETURN longname;
 END;
$$ LANGUAGE 'plpgsql' IMMUTABLE;


CREATE OR REPLACE FUNCTION osml10n_street_abbrev_en(longname text) RETURNS TEXT AS $$
 DECLARE
  match text[];
 BEGIN
  IF strpos(longname, 'Avenue') > 1 THEN
    /* Avenue is a special case because we must try to e xclude french names */
    longname = regexp_replace(longname, '(?<!^([0-9]+([èe]?r)?e )?)Avenue\M','Ave.');
  END IF;
  IF strpos(longname, 'Boulevard') > 1 THEN
    longname = regexp_replace(longname, '(?!^)Boulevard\M','Blvd.');
  END IF;

  match = regexp_matches(longname, '(Crescent|Court|Drive|Lane|Place|Road|Street|Square|Expressway|Freeway|Parkway)\M');
  IF match IS NOT NULL THEN
    longname = replace(longname, match[1], CASE match[1]
      WHEN 'Crescent' THEN 'Cres.'
      WHEN 'Court' THEN 'Ct'
      WHEN 'Drive' THEN 'Dr.'
      WHEN 'Lane' THEN 'Ln.'
      WHEN 'Place' THEN 'Pl.'
      WHEN 'Road' THEN 'Rd.'
      WHEN 'Street' THEN 'St.'
      WHEN 'Square' THEN 'Sq.'

      WHEN 'Expressway' THEN 'Expy'
      WHEN 'Freeway' THEN 'Fwy'
      WHEN 'Parkway' THEN 'Pkwy'
    END);
  END IF;

  match = regexp_matches(longname, '(North|South|West|East|Northwest|Northeast|Southwest|Southeast)\M');
  IF match IS NOT NULL THEN
    longname = replace(longname, match[1], CASE match[1]
      WHEN 'North' THEN 'N'
      WHEN 'South' THEN 'S'
      WHEN 'West' THEN 'W'
      WHEN 'East' THEN 'E'
      WHEN 'Northwest' THEN 'NW'
      WHEN 'Northeast' THEN 'NE'
      WHEN 'Southwest' THEN 'SW'
      WHEN 'Southeast' THEN 'SE'
    END);
  END IF;

  RETURN longname;
 END;
$$ LANGUAGE 'plpgsql' IMMUTABLE;
