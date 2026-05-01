-- 1. Получить информацию о всех гномах, которые входят в какой-либо отряд, вместе с информацией об их отрядах.
-- Гном может не входить в отрят, тогда с помощью INNER JOIN я отфильтрую только входящих в отряды гномов.
SELECT dw.*, sqd.* FROM dwarves dw INNER JOIN squads sqd ON dw.squad_id = sqd.squad_id;

-- 2. Найти всех гномов с профессией "miner", которые не состоят ни в одном отряде.
-- Проверка поля на null согласно спецификации поля в схема.
SELECT * FRON dwarves WHERE profession = 'miner' AND squad_id IS NULL;

-- 3. Получить все задачи с наивысшим приоритетом, которые находятся в статусе "pending".
-- Использую оконную функцию ранжирования по полю 'status'. Если есть повторияющиеся значения приоритета, то функция RANK() вернет одинаковое значение.
-- Таким образом выборка будет состоять из множества задач с наивысшим приоритетом, а не из одной.
SELECT task_id, description, assigned_to, status 
FROM (
	SELECT task_id, description, assigned_to, status, RANK() OVER (PARTITION BY status ORDER BY priority) AS rnk FROM tasks
) ranked_tasks
WHERE status = 'pending' AND rnk = 1;

-- 4. Для каждого гнома, который владеет хотя бы одним предметом, получить количество предметов, которыми он владеет.
-- INNER JOIN выберет только гномов с минимум одним предметом.
SELECT dw.dwarf_id, dw.name, COUNT(i.item_id) AS item_count
FROM dwarves dw INNER JOIN items i ON dw.dwarf_id = i.owner_id
GROUP BY dw.dwarf_id, dw.name;

-- 5. Получить список всех отрядов и количество гномов в каждом отряде. Также включите в выдачу отряды без гномов.
-- LEFT JOIN включит в выдачу отряды без гномов. В отрядах без гномов COUNT(dw.dwarf_id) вернет 0.
SELECT sqd.squad_id, sqd.name, sqd.mission, COUNT(dw.dwarf_id) AS dwarf_count
FROM squads sqd LEFT JOIN dwarves dw ON sqd.squad_id = dw.squad_id
GROUP BY sqd.squad_id, sqd.name, sqd.mission;

-- 6. Получить список профессий с наибольшим количеством незавершённых задач ("pending" и "in_progress") у гномов этих профессий.
-- Главная сложность этого вопроса для меня состояла в коррентном выводе профессий в тот момент, когда ни один из гномов этой профессии не завершил ни одной задачи и у него нет не открытых задач.
-- INNER JOIN позволяет мне избежать вырожденного случая, когда полное отсутсвие задач у профессии делает ее самой загруженной.
-- Ранжирование через RANK() == 1 при убывании количества открытых задач вернет несколько профессий с одинаковым максимальным числом о открытых задач.
WITH ranked_professions AS (
	SELECT dw.profession AS profession, COUNT(t.status) AS uncompleted_count, RANK() OVER (ORDER BY uncompleted_count DESC) AS rnk
	FROM dwarves dw INNER JOIN tasks t ON dw.dwarf_id = t.assigned_to AND t.status IN ('pending', 'in_progress')
	GROUP BY dw.profession
)
SELECT profession, uncompleted_count FROM ranked_professions WHERE rnk = 1;

-- 7. Для каждого типа предметов узнать средний возраст гномов, владеющих этими предметами.
-- Так как джоины создают декартово произведение строк, то в случае данного задания это может привести к тому, что возраст владельца предмета определенного типа может просуммироваться n раз.
-- Решение этой проблемы - поиск уникальных значений по типу предмета и id гнома в таблице items до того, как будет выполнено соединение и группировка.
SELECT i.type, AVG(dw.age) AS avg_age 
FROM (SELECT DISTINCT type, owner_id FROM items) i LEFT JOIN dwarves dw ON i.owner_id = dw.dwarf_id
GROUP BY i.type;

-- 8. Найти всех гномов старше среднего возраста (по всем гномам в базе), которые не владеют никакими предметами.
-- Проверку владения преметом сделал через функцию EXISTS(), так как она прерывается при первом совпадении в отличае от соединений.
-- Поиск среднего через оконную функцию без определения окна сделал для сокращения размера подзапроса благодаря отсутствию GROUP BY.
SELECT dw.dwarf_id, dw.name, dw.age, dw.profession, dw.squad_id 
FROM (SELECT dwarf_id, name, age, profession, squad_id, AVG(age) OVER () AS avg_age FROM dwarves) dw
WHERE dw.age > dw.avg_age AND NOT EXISTS (
	SELECT 1 FROM items i WHERE i.owner_id = dw.dwarf_id
);

-- ВЫВОД:
-- Главной трудностью был учет граничных случаев в моих запросах. INNER JOIN и LEFT JOIN могут приводить к кардинально противоположным результатам на границах.
-- Во всех задачах, где проблемы в запросах могли случаться на границах, были поля сущностей, которые относили элементы к различным подгруппами (профессия гнома и тип предмета).
-- Если требуется определить метрики подгрупп по связанным сущностям, то необходимо проверка на дубли и лишние вхождения в выборку.

-- РЕФЛЕКСИЯ ПО ЭТАЛОННЫМ РЕШЕНИЯМ
-- 3. Если бы я в своем вложенном select с оконной функцией по полю статус делал выборку в статусе 'pending', тогда окно бы не нужно было.
-- Дальше, RANK() OVER (ORDER BY priority) rnk -> rnk = 1 - это то же, что и MIN(priority). Я исходил из предпосылки, что чем ниже чисто, тем выше приоритет.
--
-- 6. Мой запрос отличается от эталонного тем, что выведет только те профессии, у которых число задач открытых максимальное среди всех других задач.
-- Думаю, так же мог заменить RANK() на MAX(uncompleted_count).
--
-- 8. Мог убрать поиск среднего через оконную функцию и упростить вложенный select как в эталонном решении.
-- (SELECT owner_id FROM Items) из эталонного решения выполнится только один раз, так как в нем нет зависимости на поля из внешнего запроса. Моя функция exists() будет вызываться n раз.