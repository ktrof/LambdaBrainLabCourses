-- Напишите запрос, который определит наиболее и наименее успешные экспедиции, учитывая:
-- - Соотношение выживших участников к общему числу
-- - Ценность найденных артефактов
-- - Количество обнаруженных новых мест
-- - Успешность встреч с существами (отношение благоприятных исходов к неблагоприятным)
-- - Опыт, полученный участниками (сравнение навыков до и после)
--
-- Основные вопросы:
-- - буду исходить из предположения, что таблица dwarf-skills является таблицей с историей изменения навыка гнома, иначе я не смогу узнать,
--   сколько повышений уровня навыка произошло за временной период экспедиции

-- Поскольку требуется связать много таблиц, то необходимо избежать декартова произведения строк этих таблиц (expedition_id во многих посвторяется много раз).
-- Я сделаю агрегаты по каждому показателю с группировкой по expedition_id:
-- 1. Агрегат по членам экспедиции;
-- 2. Агрегат по навыкам;
-- 3. Агрегат по артефактам;
-- 4. Агрегат по обнаруженным местам;
-- 5. Агрегат существ.
-- Буду выводить статистику по каждой экспедиции. Гномы в экспедиции могут не улучшить навыки, не биться с существами
-- или не добыть артефакты. NULL-значения заменю на 0 с помощью COALESCE().

-- Для определния значения overall_success_score все пять показателей из аггрегатов нормализовывал в диапозон от 0 до 1.
-- Использую формулу нормазилации f = (xi - min(Xi)/max(Xi) - min(Xi), где min(Xi) = 0, так как выше писал, что гномы могут закончить без результатов.
-- Получается overall_success_score = sum(K*Xi/max(Xi)), где K - это переменный вес коэфа, X - значение какого-либо показателя, i - номер экспедиции.
-- Для выжимаемости попробую задать вес 0.4, для победы над существами - 0.3, а для остальных по 0.1.
WITH
members_agg AS (
    SELECT expedition_id, COUNT(dwarf_id) AS total_members, COUNT(CASE WHEN survived IS TRUE THEN 1 END) AS survived_members
    FROM expedition_members
    GROUP BY expedition_id
),
skills_agg AS (
    SELECT em.expedition_id, COUNT(ds.skill_id) AS total_skill_improvements
    FROM expedition_members em
    JOIN dwarf_skills ds ON ds.dwarf_id = em.dwarf_id
    JOIN expeditions e ON e.expedition_id = em.expedition_id
    WHERE ds.date BETWEEN e.departure_date AND e.return_date
    GROUP BY em.expedition_id
),
artifacts_agg AS (
    SELECT expedition_id, COALESCE(SUM(value), 0) AS total_artifact_value
    FROM expedition_artifacts
    GROUP BY expedition_id
),
sites_agg AS (
    SELECT expedition_id, COUNT(site_id) AS discovered_sites
    FROM expedition_sites
    GROUP BY expedition_id
),
creatures_agg AS (
    SELECT expedition_id, COUNT(creature_id) as total_creatures, COUNT(CASE WHEN outcome = 'defeated' THEN 1 END) as defeated_creatures
    FROM expedition_creatures
    GROUP BY expedition_id
),
report AS (
    SELECT
        e.expedition_id,
        e.destination,
        e.status,
        COALESCE(m.survived_members, 0) * 100.0 / NULLIF(m.total_members, 0) AS survival_rate,
        COALESCE(c.successful_encounters, 0) * 100.0 / NULLIF(c.total_encounters, 0) AS encounter_success_rate,
        COALESCE(a.total_artifacts_value, 0) AS artifacts_value,
        COALESCE(s.discovered_sites_count, 0) AS discovered_sites,
        COALESCE(sk.total_skill_improvements, 0) AS skill_improvement,
        (e.return_date - e.departure_date) AS expedition_duration
    FROM expeditions e
        LEFT JOIN members_agg m ON m.expedition_id = e.expedition_id
        LEFT JOIN artifacts_agg a ON a.expedition_id = e.expedition_id
        LEFT JOIN sites_agg s ON s.expedition_id = e.expedition_id
        LEFT JOIN creatures_agg c ON c.expedition_id = e.expedition_id
        LEFT JOIN skills_agg sk ON sk.expedition_id = e.expedition_id
    WHERE e.status = 'Completed'
)
SELECT JSON_ARRAYAGG(JSON_OBJECT(
    KEY 'expedition_id' VALUE r.expedition_id,
    KEY 'destination' VALUE r.destination,
    KEY 'status' VALUE r.status,
    KEY 'survival_rate' VALUE ROUND(r.survival_rate, 2),
    KEY 'artifacts_value' VALUE r.artifacts_value,
    KEY 'discovered_sites' VALUE r.discovered_sites,
    KEY 'encounter_success_rate' VALUE ROUND(r.encounter_success_rate, 2),
    KEY 'skill_improvement' VALUE r.skill_improvement,
    KEY 'expedition_duration' VALUE r.expedition_duration,
    KEY 'overall_success_score' VALUE ROUND(
        (
            0.4 * (r.survival_rate / MAX(r.survival_rate)) +
            0.3 * (r.encounter_success_rate / MAX(r.encounter_success_rate)) +
            0.1 * (r.artifacts_value / MAX(r.artifacts_value)) +
            0.1 * (r.discovered_sites / MAX(r.discovered_sites)) +
            0.1 * (r.skill_improvement / MAX(r.skill_improvement))
        ),
        2
    ),
    KEY 'related_entities' VALUE JSON_OBJECT(
        KEY 'member_ids' VALUE (
            SELECT JSON_ARRAYAGG(em.dwarf_id)
            FROM expedition_members em
            WHERE em.expedition_id = e.expedition_id
        ),
        KEY 'artifact_ids' VALUE (
            SELECT JSON_ARRAYAGG(ea.artifact_id)
            FROM expedition_artifacts ea
            WHERE ea.expedition_id = e.expedition_id
        ),
        KEY 'site_ids' VALUE (
            SELECT JSON_ARRAYAGG(es.site_id)
            FROM expedition_sites es
            WHERE es.expedition_id = e.expedition_id
        ),
    )
)) FROM report;

-- РЕФЛЕКСИЯ ПО ЭТАЛОННОМУ РЕШЕНИЮ
--
-- 1. Декартово произведение строк в общем табличном представлении expedition_stats эталонного решения.
-- Таблицы соединяются слева направо: сначала таблица из FROM соединиться с первой таблицей, формируя попарное произведение,
-- а затем в этому результату присоединиться следующая таблица и так далее.
-- GROUP BY будет выполнен для этого попарного произведения, и аггрегатные функции будут выдавать завышенный результат.
-- Решением может быть выполнение предварительного агрегирующего подзапроса, который вернет одну строку.
-- В моем решении в агрегатах для каждой экспедиции создается одна строка, и соединения по expedition_id по каждому агрегату выполняются 1*1*1 и т.д. раз.
--
-- 2. Сравнение поведения skills_progression из эталонного решения с моим skills_agg.
-- В эталонном решении происходит выборка скиллов гномов из экспедиции до ее начала и после окончания, затем по экспедиции выполняется сумма
-- разности уровней каждой записи из объединения гнома из экспедиции и его навыка. Учитывается только повышение существовавших на начало экспедиции навыков.
-- Учитывается повышение больше одного уровня навыка за раз.
-- Мое решение считает новые записи в таблице dwarf_skills для каждого гнова экспедиции между началом и окончанием экспедиции.
-- Учитывается приобретение и повышение не только существующих, но и новых навыков. Не учиытвается повышение навыка более чем на 1 уровнень.
--
-- 3. Поле overall_success_score
-- В эталонном решении значение поля overall_success_score не зависит от других экспедиций, таким образом при повтором запросе этого отчета
-- overall_success_score всегда будет один и тот же при добавлении новых экспедиций. При достаточно большой стоимости артефактов
-- или поднятых навыков значение overall_success_score перевалит за 1.
-- В моем решенении присутствует зависимость на max показатели других экспедиций для нормализации каждого показателя, из-за чего
-- при добавлении новых экспедиций поле overall_success_score при перезапросе будет меняться, но не превысит 1.