-- Создайте запрос, который возвращает информацию о гноме, включая идентификаторы всех его навыков, текущих назначений, принадлежности к отрядам и используемого снаряжения.
SELECT JSON_ARRAYAGG(JSON_OBJECT(
    KEY 'dwarf_id' VALUE d.dwarf_id,
    KEY 'name' VALUE d.name,
    KEY 'age' VALUE d.age,
    KEY 'profession' VALUE d.profession,
    KEY 'related_entities' VALUE JSON_OBJECT(
        KEY 'skill_ids' VALUE (
            SELECT JSON_ARRAYAGG(ds.skill_id ORDER BY ds.skill_id)
            FROM dwarf_skills ds
            WHERE ds.dwarf_id = d.dwarf_id
        ),
        KEY 'assignment_ids' VALUE (
            SELECT JSON_ARRAYAGG(da.assignment_id ORDER BY da.assignment_id)
            FROM dwarf_assignments da
            WHERE da.dwarf_id = d.dwarf_id
        ),
        KEY 'squad_ids' VALUE (
            SELECT JSON_ARRAYAGG(sm.squad_id ORDER BY sm.squad_id)
            FROM squad_members sm
            WHERE sm.dwarf_id = d.dwarf_id
        ),
        KEY 'equipment_ids' VALUE (
            SELECT JSON_ARRAYAGG(de.equipment_id ORDER BY de.equipment_id)
            FROM dwarf_equipment de
            WHERE de.dwarf_id = d.dwarf_id
        )
    )
)) FROM d dwarves;

-- Напишите запрос для получения информации о мастерской, включая идентификаторы назначенных ремесленников, текущих проектов, используемых и производимых ресурсов.
SELECT JSON_ARRAYAGG(JSON_OBJECT(
    KEY 'workshop_id' VALUE ws.workshop_id,
    KEY 'name' VALUE ws.name,
    KEY 'type' VALUE ws.type,
    KEY 'quality' VALUE ws.quality,
    KEY 'related_entities' VALUE JSON_OBJECT(
        KEY 'craftsdwarf_ids' VALUE (
            SELECT JSON_ARRAYAGG(cd.dwarf_id ORDER BY cd.dwarf_id)
            FROM workshop_craftsdwarves cs
            WHERE cs.workshop_id = ws.workshop_id
        ),
        KEY 'project_ids' VALUE (
            SELECT JSON_ARRAYAGG(p.project_id ORDER BY p.project_id)
            FROM projects p
            WHERE p.workshop_id = ws.workshop_id
        ),
        KEY 'input_material_ids' VALUE (
            SELECT JSON_ARRAYAGG(m.material_id ORDER BY m.material_id)
            FROM workshop_materials m
            WHERE m.workshop_id = ws.workshop_id AND m.is_input IS TRUE
        ),
        KEY 'output_product_ids' VALUE (
            SELECT JSON_ARRAYAGG(wp.product_id ORDER BY wp.product_id)
            FROM workshop_products wp
            WHERE wp.workshop_id = ws.workshop_id
        )
    )
)) FROM ws workshops;

-- Разработайте запрос, который возвращает информацию о военном отряде, включая идентификаторы всех членов отряда, используемого снаряжения, прошлых и текущих операций, тренировок.
SELECT JSON_ARRAYAGG(JSON_OBJECT(
    KEY 'squad_id' VALUE ms.workshop_id,
    KEY 'name' VALUE ms.name,
    KEY 'formation_type' VALUE ms.formation_type,
    KEY 'leader_id' VALUE ms.leader_id,
    KEY 'related_entities' VALUE JSON_OBJECT(
        KEY 'member_ids' VALUE (
            SELECT JSON_ARRAYAGG(sm.dwarf_id ORDER BY sm.dwarf_id)
            FROM squad_members sm
            WHERE sm.squad_id = ms.squad_id
        ),
        KEY 'equipment_ids' VALUE (
            SELECT JSON_ARRAYAGG(se.equipment_id ORDER BY se.equipment_id)
            FROM squad_equipment se
            WHERE se.squad_id = ms.squad_id
        ),
        KEY 'operation_ids' VALUE (
            SELECT JSON_ARRAYAGG(so.operation_id ORDER BY so.operation_id)
            FROM squad_operations so
            WHERE so.squad_id = ms.squad_id
        ),
        KEY 'training_schedule_ids' VALUE (
            SELECT JSON_ARRAYAGG(st.schedule_id ORDER BY st.schedule_id)
            FROM squad_training st
            WHERE st.squad_id = ms.squad_id
        ),
        KEY 'battle_report_ids' VALUE (
            SELECT JSON_ARRAYAGG(sb.report_id ORDER BY sb.report_id)
            FROM squad_battles sb
            WHERE sb.squad_id = ms.squad_id
        )
    )
)) FROM ms military_squads;