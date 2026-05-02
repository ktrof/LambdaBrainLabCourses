-- 1. Найдите все отряды, у которых нет лидера.
SELECT squad_id, name FROM squads WHERE leader_id IS NULL;

-- 2. Получите список всех гномов старше 150 лет, у которых профессия "Warrior".
SELECT * FROM dwarves WHERE age > 150 AND profession = 'Warrior';

-- 3. Найдите гномов, у которых есть хотя бы один предмет типа "weapon".
SELECT dw.dwarf_id, dw.name, dw.age, dw.profession FROM dwarves dw
WHERE EXISTS(SELECT 1 FROM items i WHERE dw.dwarf_id = i.owner_id AND type = 'weapon');

-- 4. Получите количество задач для каждого гнома, сгруппировав их по статусу.
-- Поскольку требуется вывести количество задач для каждого гнома, то обычное пересечение dwarves и tasks по dwarf_id уберет из выборки гномов без задач.
-- Если использовать левый джион для вывода всех гномов, то у гномов без задач поле статус будет null, а количество 0.
-- Я перемножил dwarves с уникальными значениями статусов, чтобы у любого гнома были все статусы, затем использовал левый джоин по равенству идентификаторов гномов и статусов.
-- После группировки будет выведена информация по каждому гному с количеством задач всех статусов (0 если задач в данном статусе нет).
SELECT dw.dwarf_id, dw.name, st.status, COUNT(t.task_id) task_count
FROM dwarves dw
    CROSS JOIN (SELECT DISTINCT status FROM tasks) st
    LEFT JOIN tasks t ON dw.dwarf_id = t.assigned_to AND st.status = t.status
GROUP BY dw.dwarf_id, dw.name, st.status;

-- 5. Найдите все задачи, которые были назначены гномам из отряда с именем "Guardians".
SELECT t.task_id, t.description, t.status
FROM tasks t
    JOIN dwarves dw ON t.owner_id = dw.dwarf_id
    JOIN squads sqd ON dw.squad_id = sqd.squad_id AND sqd.name = 'Guardians'


-- 6. Выведите всех гномов и их ближайших родственников, указав тип родственных отношений.
SELECT
    dw.dwarf_id AS dwarf_id,
    dw.name AS name,
    dw.age AS age,
    dw.profession AS profession,
    othr.dwarf_id AS other_dwarf_id,
    othr.name AS other_name,
    othr.age AS other_age,
    othr.profession AS other_profession,
    rl.relationship AS relationship
FROM relationships rl
    JOIN dwarves dw ON rl.dwarf_id = dw.dwarf_id
    JOIN dwarves othr ON rl.related_to = othr.dwarf_id
