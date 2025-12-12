/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Лапшина Виктория
 * Дата: 25.01.2025
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
SELECT COUNT(payer) AS total_players, -- общее кол-во игроков
SUM(payer) AS total_payers, -- кол-во платящих игроков
round(AVG(payer),2) AS payers_proportion -- доля платящих игроков
FROM fantasy.users;
-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
SELECT r.race, SUM(payer) AS total_payers, 
COUNT(payer) AS total_players, 
round(AVG(payer),2) AS payers_proportion
FROM fantasy.race r 
JOIN fantasy.users u USING(race_id) 
GROUP BY r.race
ORDER BY total_payers DESC;
-- Задача 2. Исследование внутриигровых покупок 
-- 2.1. Статистические показатели по полю amount:
SELECT count(transaction_id) AS total_events, sum(amount) AS total_amount, -- общее кол-во покупок и общая сумма
min(amount) AS min_amount, max(amount) AS max_amount, avg(amount) AS avg_amount, -- минимальное, максисмальное и среднее занчения
percentile_cont(0.5) WITHIN GROUP (ORDER BY amount) AS median, stddev(amount) -- разброс данных
FROM fantasy.events e;
-- 2.2: Аномальные нулевые покупки:
SELECT COUNT(amount) AS null_trasact, -- кол-во нулевых покупок(с фильтром)
(COUNT(amount)::FLOAT / (SELECT COUNT(amount) FROM fantasy.events)) AS nulltransact_proportion -- в подзапросе считаем общее кол-во покупок
FROM fantasy.events 
WHERE amount = 0;
-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:
SELECT CASE -- разделяем на категории
	WHEN payer=1 THEN 'Платящие'
	WHEN payer=0 THEN 'Неплатящие'
END AS player_type,
count(DISTINCT e.id) AS total_players, -- кол-во активно покупающих игроков
round(count(transaction_id)::numeric/count(DISTINCT e.id), 2) AS avg_transactions, -- среднее число покупок
round(sum(amount)::numeric/count(DISTINCT e.id), 2) AS avg_amount -- средня суммарная стоимость
FROM fantasy.events e 
JOIN fantasy.users u USING(id)
WHERE e.amount > 0 -- исключаем нулевые покупки
GROUP BY player_type;
-- 2.4: Популярные эпические предметы:
WITH item_totals AS (SELECT game_items, count(e.transaction_id) AS total_amount, count(DISTINCT e.id) AS buyers
FROM fantasy.items i
LEFT JOIN fantasy.events e USING(item_code) 
GROUP BY game_items)
SELECT game_items, total_amount, 
ROUND(total_amount::numeric/(SELECT count(transaction_id) FROM fantasy.events e WHERE amount>0),7) AS trans_proportion, -- Относительное значение
ROUND(buyers::NUMERIC/(SELECT count(id) AS total_players FROM fantasy.users),5) AS players_proportion -- доля игроков, которые хотя бы раз покупали предмет
FROM item_totals
ORDER BY total_amount DESC;
-- Часть 2. Решение ad hoc-задач
-- Задача 1. Зависимость активности игроков от расы персонажа:
WITH players AS (SELECT race_id, count(DISTINCT id) AS total_players
				 FROM fantasy.users u
				 GROUP BY race_id),
payers AS (SELECT race_id, count(DISTINCT e.id) AS total_payers -- общее кол-во платящих активных игроков
			FROM fantasy.users u
			JOIN fantasy.events e USING(id)
			WHERE payer=1 AND amount > 0
			GROUP BY race_id),
buyers AS (SELECT u.race_id, count(DISTINCT e.id) AS total_buyers -- общее кол-во игроков, совершающих покупки
			FROM fantasy.users u
			INNER JOIN fantasy.events e USING(id) 
			WHERE e.amount>0 -- исключаем нулевые покупки
			GROUP BY u.race_id),
cte_totals AS (SELECT race_id, total_players, total_buyers, -- обединяем первые 3 cte
						round(total_buyers::numeric/total_players, 2) AS buyers_proportion, -- доля игроков, совершающих покупки, от общегго кол-ва
						round(total_payers::numeric/total_buyers, 2) AS payers_proportion -- доля платящих игроков от совершающих покупки
				FROM players p
				JOIN payers USING(race_id)
				JOIN buyers USING(race_id)),
events_totals AS (SELECT u.race_id, e.id, count(e.transaction_id) AS total_events, avg(amount) AS avg_amount, sum(amount) AS total_sum -- активность игроков для последующих расчетов
					FROM fantasy.users u
					JOIN fantasy.events e USING(id)
					WHERE e.amount>0 -- исключаем нулевые покупки
					GROUP BY u.race_id, e.id)
SELECT r.race, ct.total_players, ct.total_buyers, ct.buyers_proportion, ct.payers_proportion, -- собираем все вместе
		round(avg(et.total_events),2) AS avg_events, -- среднее количество покупок на одного игрока
		round(avg(et.total_sum)::NUMERIC/avg(et.total_events),2) AS avg_amount_per_user, -- средняя стоимость одной покупки на одного игрока
		round(avg(total_sum)::numeric,2) AS avg_sum -- средняя суммарная стоимость всех покупок на одного игрока
FROM fantasy.race r
JOIN cte_totals ct USING(race_id)
JOIN events_totals et USING(race_id)
GROUP BY r.race, ct.total_players, ct.total_buyers, ct.buyers_proportion, ct.payers_proportion
ORDER BY ct.total_players DESC;
-- Задача 2: Частота покупок
WITH events_totals AS (SELECT id, count(transaction_id) AS total_events, -- кол-во покупок
			date::date-LAG(date::date, 1) OVER(PARTITION BY id ORDER BY date::date) AS days_between -- кол-во дней между датами покупок
FROM fantasy.events e
WHERE amount<>0 -- исключаем нулевые покупки
GROUP BY id, date::date
ORDER BY id, date::date),
total_count AS (SELECT et.id AS buyers, u.id AS payers, -- добавляем платящих  игроков
		sum(total_events) AS events, -- общее кол-вопокупок на игрока
		round(avg(days_between), 2) AS events_freq, -- среднее кол-во дней между покупками на игрока
		NTILE(3) OVER(ORDER BY avg(days_between) ASC) AS ranking -- делим на три группы
		FROM events_totals et
LEFT JOIN (SELECT id FROM fantasy.users WHERE payer = 1) u USING(id) 
GROUP BY buyers, u.id
HAVING sum(total_events)>25 -- исключаем игроков с маленьким кол-вом покупок
ORDER BY events_freq ASC)
SELECT CASE 
	WHEN ranking=1 THEN 'высокая частота'
	WHEN ranking=2 THEN 'умеренная частота'
	WHEN ranking=3 THEN 'низкая частота'
END AS user_group,
count(buyers) AS total_players, count(payers) AS payers, -- считаем игроков
round(count(payers)::NUMERIC/count(buyers),2) AS payers_part, -- доля платящих игроков, совершивших покупки, от общего кол-ва игроков, совершивших покупки
round(avg(events),2) AS avg_events, -- среднее кол-во покупок
round(avg(events_freq),2) AS frequency -- средняя частота покупок
FROM total_count
GROUP BY user_group; -- Частота покупок