-- Напишите SQL запрос, который возвращает данные о крепости, включая список идентификаторов всех проживающих гномов,
-- доступных ресурсов, построенных мастерских и военных отрядов.
--
-- Немного преобразую возможное решение, чтобы SELECT сразу вощвращал json-массив по записям таблицы fortresses.
-- (https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/JSON_OBJECT.html)
SELECT JSON_ARRAYAGG(JSON_OBJECT(
    'fortress_id', f.fortress_id,
    'name', f.name,
    'location', f.location,
    'founded_year', f.founded_year,
    'related_entities', JSON_OBJECT(
        'dwarf_ids', (
            SELECT JSON_ARRAYAGG(d.dwarf_id)
            FROM dwarves d
            WHERE d.fortress_id = f.fortress_id
        ),
        'resource_ids', (
            SELECT JSON_ARRAYAGG(fr.resource_id)
            FROM fortress_resources fr
            WHERE fr.fortress_id = f.fortress_id
        ),
        'workshop_ids', (
            SELECT JSON_ARRAYAGG(w.workshop_id)
            FROM workshops w
            WHERE w.fortress_id = f.fortress_id
        ),
        'squad_ids', (
            SELECT JSON_ARRAYAGG(s.squad_id)
            FROM military_squads s
            WHERE s.fortress_id = f.fortress_id
        )
    )
) ORDER BY f.population DESC)
FROM fortresses f;

-- Функция JSON_ARRAYAGG (https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/JSON_ARRAYAGG.html)
-- Данная фунция приводит все строки таблица по sql-выражению в json-массив с возможностью задания сортировки,
-- фильтрации, валидации и спецификации представления возвращаемого json-массива.
-- В преобразованном мной запросе я добавляю сортировку крепостей по убыванию численности населения.