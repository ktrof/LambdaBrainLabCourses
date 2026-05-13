-- Создайте запрос, оценивающий эффективность военных отрядов на основе:
-- - Результатов всех сражений (победы/поражения/потери)
-- - Соотношения побед к общему числу сражений
-- - Навыков членов отряда и их прогресса
-- - Качества экипировки
-- - Истории тренировок и их влияния на результаты
-- - Выживаемости членов отряда в долгосрочной перспективе

-- Введу некоторые допущения в расчет параметров:
--
-- - Параметр casualty_rate.
--   Пусть в поле squad_members.casualties записываются потери членов отряда -> смерть и выбывание из отряда.
--   Тогда casualty_rate буду считать как процент от общих потерь отряда за всё время к общей численности отряда за всё время.
--   Как вариант ещё рассмотреть систему нокаутов: тогда я бы общее число потерь делил на произведение общей численности на общее число битв.
--
-- - Параметр casualty_exchange_ratio.
--   Буду считать как отношение суммы потерь врагов к сумме потерь отряда.
--
-- - Параметр avg_equipment_quality.
--   Пусть в таблице squad_equipment хранятся ссылки на снаряжение гномов. Тогда количество одинавого снаряжения на разных гномах в отряде
--   запишется в поле squad_equipment.quantity, следовательно среднюю ценность снаряжение можно считать как средневзвешенное по количеству в отряде.
--
-- - Параметр total_training_sessions.
--   Буду считать как общее число записей о тренировках в отряде.
--
-- - Параметр training_battle_correlation.
--   Для корректного подсчета коэффициента корреляции необходимо иметь равный размер выборок случайных величин.
--   Пусть первая случайная величина - победа или поражение в бою (0 или 1 в зависимости от outcome), а вторая - средняя эффективность
--   тренировок строго после прошлого сражения и строго перед текущим сражением (с помощью LAG() буду искать прошлую дату сражения или пропускать при NULL).
--   Пусть средняя эффективность тренировок равно 0, если перед сражением не было тренировок или они были безрезультатны.
--   Буду искать корреляцию между средней эффективность тренировок до сражения и исходом сражения по коэффициенту корреляции Пирсона - CORR().
--
-- - Параметр avg_combat_skill_improvement.
--   Пусть значение параметра равно отношению общего числа поднятых навыков всеми членами в отряде к общему количеству сражений.
--   Известно, что таблица squad_members содержит историю членства за временной период, и один гном может выйти из отряда, а затем вернуться туда позже.
--   Расширю таблицу squad_members полем levels_upgraded, которое будет считать сумму дельт уровней навыков за период членства в отряде.
--   Временной интервал может быть не ограничен свеху, если гном не уходил из отряда на момент запроса.
--   В результате расширения таблицы для каждой исторической записи о членстве гнома добавляется количество поднятых уровней этим гномом.
--
-- - Параметр overall_effectiveness_score.
--   Буду использовать нормализованные параметры victory_percentage, 1 - casualty_rate, retention_rate, avg_training_effectiveness,
--   training_battle_correlation, casualty_exchange_ratio, avg_equipment_quality, total_training_sessions
--   с весами 0.2, 0.2, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1.
--
--   Параметры casualty_exchange_ratio, avg_equipment_quality, total_training_sessions - количественные,
--   поэтому буду нормализовывать по максимальному значению среди всех отрядов.

WITH
-- CTE формирования и обогащения данных для агрегирования
skill_improvements AS (
    SELECT ds.dwarf_id,
           ds.skill_id,
           ds.date,
           -- Если навык был приобретен впервые, то дельта равна уровню нового навыка (опыта в новом навыке может хватить сразу на несколько уровней).
           -- Группирую по гному и затем навыку, чтобы не посчитать лищние навыки. Сортирую сначала по дате, а потом по уровню, если в одно время было поднято несколько уровней.
           ds.level - COALESCE(LAG(ds.level) OVER (PARTITION BY ds.dwarf_id, ds.skill_id ORDER BY ds.date, ds.level), 0) AS level_delta
    FROM dwarf_skills ds
),
members AS (
    SELECT sm.squad_id,
           sm.dwarf_id,
           sm.join_date,
           sm.exit_date,
           (
               -- Этот коррелирующий подзапрос считает поднятые уровни как существующих, так и новых навыков за временной интервал членства в отряде.
               SELECT SUM(si.level_delta)
               FROM skill_improvements si
               WHERE si.dwarf_id = sm.dwarf_id
               AND si.date > sm.join_date
               AND (sm.exit_date IS NULL OR si.date < sm.exit_date)
           ) AS levels_upgraded
    FROM squad_members sm
),
battles AS (
    SELECT sb.squad_id,
           sb.report_id,
           sb.date,
           LAG(sb.date) OVER (PARTITION BY sb.squad_id ORDER BY sb.date) as prev_date,
           sb.outcome,
           sb.casualties,
           sb.enemy_casualties
    FROM squad_battles sb
),
battle_training_pairs AS (
    SELECT sb.squad_id,
        sb.report_id,
        CASE WHEN sb.outcome = 'victory' THEN 1 ELSE 0 END AS is_victory,
        (
            -- Этот коррелирующий подзапрос вернет среднюю эффективность тренировок строго после прошлого и перед текущим сражением.
            SELECT AVG(st.effectiveness)
            FROM squad_training st
            WHERE st.squad_id = sb.squad_id
            AND st.date < sb.date
            AND (sb.prev_date IS NULL OR st.date > sb.prev_date)
        ) AS prior_avg_effectiveness
    FROM battles sb
),
-- CTE агрегирования
training_battle_correlations AS (
    SELECT squad_id,
           CORR(prior_avg_effectiveness, is_victory) as training_battle_correlation
    FROM battle_training_pairs
    GROUP BY squad_id
),
members_agg AS (
    SELECT squad_id,
           -- Считаю только уникальные появления гнома в отряде.
           COUNT(DISTINCT CASE WHEN exit_date IS NULL THEN dwarf_id END) AS current_members,
           COUNT(DISTINCT dwarf_id) AS total_members_ever,
           SUM(levels_upgraded) AS total_skill_upgrades
    FROM members m
    GROUP BY squad_id
),
equipment_agg AS (
    SELECT se.squad_id,
           SUM(se.quantity * e.quality) / SUM (se.quantity) AS avg_equipment_quality
    FROM squad_equipment se JOIN equipment e ON se.equipment_id = e.equipment_id
    GROUP BY se.squad_id
),
battles_agg AS (
    SELECT squad_id,
           COUNT(report_id) as total_battles,
           COUNT(CASE WHEN outcome = 'victory' THEN report_id END) AS victories,
           SUM(COALESCE(casualties, 0)) AS total_casualties,
           SUM(COALESCE(enemy_casualties, 0)) AS total_enemy_casualties
    FROM battles
    GROUP BY squad_id
),
training_agg AS (
    SELECT squad_id,
           COUNT(schedule_id) AS total_training_sessions,
           AVG(effectiveness) AS avg_training_effectiveness
    FROM squad_training
    GROUP BY squad_id
),
-- CTE отчета эффетивности отрядов
report AS (
    SELECT ms.squad_id,
           ms.squad_name,
           ms.formation_type,
           d.name AS leader_name,
           b.total_battles,
           b.victories,
           ROUND(CAST(b.victories AS DECIMAL) * 100 / NULLIF(b.total_battles, 0), 2) AS victory_percentage,
           ROUND(CAST(b.total_casualties AS DECIMAL) * 100 / NULLIF(m.total_members_ever, 0), 2) AS casualty_rate,
           ROUND(
                   -- Если гномы заканчивали сражения без потерь, тогда значение параметра равно общему числу потерь врагов.
                   CASE
                       WHEN b.total_casualties = 0 THEN CAST(b.total_enemy_casualties AS DECIMAL)
                       ELSE CAST(b.total_enemy_casualties AS DECIMAL) / b.total_casualties
                   END,
                   2
           ) AS casualty_exchange_ratio,
           m.current_members,
           m.total_members_ever,
           ROUND(CAST(m.current_members AS DECIMAL) / NULLIF(m.total_members_ever, 0), 2) AS retention_rate,
           e.avg_equipment_quality,
           t.total_training_sessions,
           t.avg_training_effectiveness,
           corr.training_battle_correlation,
           ROUND(CAST(m.total_skill_upgrades AS DECIMAL) / NULLIF(b.total_battles, 0), 2) AS avg_combat_skill_improvement
    FROM military_squads ms
    LEFT JOIN dwarves d ON d.dwarf_id = ms.leader_id
    LEFT JOIN battles_agg b ON ms.squad_id = b.squad_id
    LEFT JOIN members_agg m ON ms.squad_id = m.squad_id
    LEFT JOIN equipment_agg e ON ms.squad_id = e.squad_id
    LEFT JOIN training_agg t ON ms.squad_id = t.squad_id
    LEFT JOIN training_battle_correlations corr ON ms.squad_id = corr.squad_id
),
report_with_score AS (
    SELECT r.*,
           ROUND(
                   (
                       0.2 * COALESCE(r.victory_percentage, 0) / 100 +
                       0.2 * (1.0 - COALESCE(r.casualty_rate, 0) / 100) +
                       0.1 * COALESCE(r.retention_rate, 0) +
                       0.1 * COALESCE(r.avg_training_effectiveness, 0) +
                       0.1 * COALESCE(r.training_battle_correlation, 0) +
                       0.1 * COALESCE(r.casualty_exchange_ratio, 0) / NULLIF(MAX(r.casualty_exchange_ratio) OVER (), 0) +
                       0.1 * COALESCE(r.avg_equipment_quality, 0) / NULLIF(MAX(r.avg_equipment_quality) OVER (), 0) +
                       0.1 * COALESCE(r.total_training_sessions, 0) / NULLIF(MAX(r.total_training_sessions) OVER (), 0)
                       ),
                   2
           ) AS overall_effectiveness_score
    FROM report r
)
SELECT JSON_ARRAYAGG(JSON_OBJECT(
    KEY 'squad_id' VALUE r.squad_id,
    KEY 'squad_name' VALUE r.squad_name,
    KEY 'formation_type' VALUE r.formation_type,
    KEY 'leader_name' VALUE r.leader_name,
    KEY 'total_battles' VALUE r.total_battles,
    KEY 'victories' VALUE r.victories,
    KEY 'victory_percentage' VALUE r.victory_percentage,
    KEY 'casualty_rate' VALUE r.casualty_rate,
    KEY 'casualty_exchange_ratio' VALUE r.casualty_exchange_ratio,
    KEY 'current_members' VALUE r.current_members,
    KEY 'total_members_ever' VALUE r.total_members_ever,
    KEY 'retention_rate' VALUE r.retention_rate,
    KEY 'avg_equipment_quality' VALUE r.avg_equipment_quality,
    KEY 'total_training_sessions' VALUE r.total_training_sessions,
    KEY 'avg_training_effectiveness' VALUE r.avg_training_effectiveness,
    KEY 'training_battle_correlation' VALUE r.training_battle_correlation,
    KEY 'avg_combat_skill_improvement' VALUE r.avg_combat_skill_improvement,
    KEY 'overall_effectiveness_score' VALUE r.overall_effectiveness_score,
    KEY 'related_entities' VALUE JSON_OBJECT(
        KEY 'member_ids' VALUE (
            SELECT JSON_ARRAYAGG(DISTINCT sm.dwarf_id)
            FROM squad_members sm
            WHERE r.squad_id = sm.squad_id
        ),
        KEY 'equipment_ids' VALUE (
            SELECT JSON_ARRAYAGG(se.equipment_id)
            FROM squad_equipment se
            WHERE r.squad_id = se.squad_id
        ),
        KEY 'battle_report_ids' VALUE (
            SELECT JSON_ARRAYAGG(sb.report_id)
            FROM squad_battles sb
            WHERE r.squad_id = sb.squad_id
        ),
        KEY 'training_ids' VALUE (
            SELECT JSON_ARRAYAGG(st.schedule_id)
            FROM squad_training st
            WHERE r.squad_id = st.squad_id
        )
    )
) ORDER BY r.overall_effectiveness_score DESC) -- сортировка внутри агрегата JSON_ARRAYAGG (https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/JSON_ARRAYAGG.html)
FROM report_with_score r;