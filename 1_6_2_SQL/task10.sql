-- Разработайте запрос, который анализирует эффективность каждой мастерской, учитывая:
-- - Производительность каждого ремесленника (соотношение созданных продуктов к затраченному времени)
-- - Эффективность использования ресурсов (соотношение потребляемых ресурсов к производимым товарам)
-- - Качество производимых товаров (средневзвешенное по ценности)
-- - Время простоя мастерской
-- - Влияние навыков ремесленников на качество товаров

-- - Параметр value_per_material_unit буду считать как соотношение произведенных товаров к потребляемым ресурсам;
--   Параметр avg_product_value буду считать как средневзвешенное по ценности;
-- - Параметр average_craftsdwarf_skill буду считать так: сначала среднее значение уровня навыка каждого гнома,
--   а затем группировка по среднему значению уровней всех гномов в мастерской;
-- - Параметр material_conversion_ratio буду считать как соотношение потребляемых ресурсов к производимым товарам;
-- - Параметр workshop_utilization_percent буду считать как единица минут соотношение дней без товаров (функция LAG()) к общему числу дней работы мастерской;
-- - Параметр skill_quality_correlation буду считать по формуле коэффициента корреляции Пирсона (https://en.wikipedia.org/wiki/Correlation).
--   Так как между workshop_craftsdwarves-dwarf_skills и workshop_products-products нет явной связи, а только через общий workshop_id,
--   тогда сформирую декартово произведение между всеми навыками всех гномов и всеми производимыми товарами одной мастерской и посчитаю коэффициент корреляции по каждой паре.
WITH
craftsdwarves AS (
    SELECT wc.workshop_id,
           wc.dwarf_id,
           ds.level,
           AVG(ds.level) OVER (PARTITION BY wc.dwarf_id) AS avg_dwarf_skill -- Средний уровень каждого гнома.
    FROM workshop_craftsdwarves wc JOIN dwarf_skills ds ON wc.dwarf_id = ds.dwarf_id
),
products AS (
    SELECT wp.workshop_id,
           wp.quantity,
           p.value,
           wp.production_date,
           p.quality,
           -- Предыдущая дата для мастерской. Если нет предыдущей выбирается текущая.
           LAG(wp.production_date, 1, wp.production_date) OVER(PARTITION BY wp.workshop_id ORDER BY wp.production_date) AS prev_date
    FROM workshop_products wp JOIN products p ON wp.product_id = p.product_id
),
craftsdwarves_agg AS (
    SELECT workshop_id,
           COUNT(DISTINCT dwarf_id) AS num_craftsdwarves,
           AVG(avg_dwarf_skill) AS average_craftsdwarf_skill -- Среднее между средними уровнями гномов в мастерской.
    FROM craftsdwarves
    GROUP BY wc.workshop_id
),
products_agg AS (
    SELECT workshop_id,
           COALESCE(SUM(quantity), 0) AS total_quantity_produced,
           SUM(COALESCE(quantity, 0) * COALESCE(value, 0)) AS total_production_value,
           SUM(quantity * value) / NULLIF(SUM(quantity), 0) AS avg_weighted_value,
           COALESCE(MAX(production_date) - MIN(production_date), 0) AS total_days,
           SUM(CASE WHEN production_date - prev_date > 1 THEN 1 ELSE 0 END) AS idle_days -- Дни простоя для расчета утилизации.
    FROM products
    GROUP BY workshop_id
),
materials_agg AS (
    SELECT workshop_id,
           COALESCE(SUM(quantity), 0) AS total_quantity_consumed
    FROM workshop_materials
    WHERE is_input IS TRUE
    GROUP BY workshop_id
),
skill_quality_agg AS (
    SELECT c.workshop_id,
           (COUNT(*) * SUM(c.level * p.quality) - SUM(c.level) * SUM(p.quality)) /
           NULLIF(
                SQRT(COUNT(*) * SUM(c.level * c.level) - SUM(c.level) * SUM(c.level)) *
                SQRT(COUNT(*) * SUM(p.quality * p.quality) - SUM(p.quality) * SUM(p.quality)),
                0
           ) as skill_quality_pearson_r -- Коэффициент корреляции Пирсона.
    FROM craftsdwarves c JOIN products p ON c.workshop_id = p.workshop_id
    GROUP BY c.workshop_id
),
report AS (
    SELECT w.workshop_id,
           w.workshop_name,
           w.workshop_type,
           c.num_craftsdwarves,
           p.total_quantity_produced,
           p.total_production_value,
           p.avg_weighted_value,
           ROUND(p.total_quantity_produced / NULLIF(p.total_days, 0), 2) AS daily_production_rate,
           ROUND(p.total_production_value / NULLIF(m.total_quantity_consumed, 0), 2) AS value_per_material_unit,
           ROUND((1 - CAST(p.idle_days AS DECIMAL) / NULLIF(p.total_days, 0)) * 100, 2) AS workshop_utilization_percent,
           ROUND(m.total_quantity_consumed / NULLIF(p.total_quantity_produced, 0), 2) AS material_conversion_ratio,
           c.average_craftsdwarf_skill,
           sq.skill_quality_pearson_r
    FROM workshops w
    LEFT JOIN craftsdwarves_agg c ON w.workshop_id = c.workshop_id
    LEFT JOIN products_agg p ON w.workshop_id = p.workshop_id
    LEFT JOIN materials_agg m ON w.workshop_id = m.workshop_id
    LEFT JOIN skill_quality_agg sq ON w.workshop_id = sq.workshop_id
)
SELECT JSON_ARRAYAGG(JSON_OBJECT(
    KEY 'workshop_id' VALUE r.workshop_id,
    KEY 'workshop_name' VALUE r.workshop_name,
    KEY 'workshop_type' VALUE r.workshop_type,
    KEY 'num_craftsdwarves' VALUE r.num_craftsdwarves,
    KEY 'total_quantity_produced' VALUE r.total_quantity_produced,
    KEY 'total_production_value' VALUE r.total_production_value,
    KEY 'avg_product_value' VALUE r.avg_weighted_value,
    KEY 'daily_production_rate' VALUE r.daily_production_rate,
    KEY 'value_per_material_unit' VALUE r.value_per_material_unit,
    KEY 'workshop_utilization_percent' VALUE r.workshop_utilization_percent,
    KEY 'material_conversion_ratio' VALUE r.material_conversion_ratio,
    KEY 'average_craftsdwarf_skill' VALUE r.average_craftsdwarf_skill,
    KEY 'skill_quality_correlation' VALUE r.skill_quality_pearson_r,
    KEY 'related_entities' VALUE JSON_OBJECT(
        KEY 'craftsdwarf_ids' VALUE (
            SELECT JSON_ARRAYAGG(wc.dwarf_id)
            FROM workshop_craftsdwarves wc
            WHERE wc.workshop_id = r.workshop_id
        ),
        KEY 'product_ids' VALUE (
            SELECT JSON_ARRAYAGG(wp.product_id)
            FROM workshop_products wp
            WHERE wp.workshop_id = r.workshop_id
        ),
        KEY 'material_ids' VALUE (
            SELECT JSON_ARRAYAGG(wm.material_id)
            FROM workshop_materials wm
            WHERE wm.workshop_id = r.workshop_id
        ),
        KEY 'project_ids' VALUE (
            SELECT JSON_ARRAYAGG(p.project_id)
            FROM projects p
            WHERE p.workshop_id = r.workshop_id
        )
    )
))
FROM report r;