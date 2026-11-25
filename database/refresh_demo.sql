-- =====================================================================
--  影院订票管理系统 · 演示数据刷新脚本
--  refresh_demo.sql
--
--  作用：不重建数据库结构，只把「场次 / 订单 / 支付 / 退票 / 评论」重置，
--        并按执行当天重新生成未来 7 天的排片与样例订单。
--
--  适用场景：种子数据放了几天后场次全部过期、首页没有可买场次时，
--            执行本脚本即可恢复，比重新跑一遍 cinema_booking.sql 更快。
--
--  执行：
--    "D:\mysql\MySQL Server 8.0\bin\mysql.exe" -u root -p123456 --default-character-set=utf8mb4 < refresh_demo.sql
--
--  注意：本脚本会清空所有订单与评论数据，仅适用于开发演示环境。
-- =====================================================================
USE cinema_booking;

-- ---------------------------------------------------------------------
-- 1. 暂停锁座超时事件，避免刷新过程中新插入的待支付订单被自动取消
-- ---------------------------------------------------------------------
ALTER EVENT ev_cancel_expired_order DISABLE;

-- ---------------------------------------------------------------------
-- 2. 清空交易类数据（先关外键检查，否则 TRUNCATE 会被引用关系拦住）
-- ---------------------------------------------------------------------
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE t_order_item;
TRUNCATE TABLE t_payment;
TRUNCATE TABLE t_refund;
TRUNCATE TABLE t_comment;
TRUNCATE TABLE t_order;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- 3. 重置场次与优惠券状态
-- ---------------------------------------------------------------------
DELETE FROM t_schedule;

UPDATE t_user_coupon
SET status = 0, use_time = NULL, order_id = NULL;

-- 把用户的积分与累计消费还原成基线值，
-- 这样反复执行刷新脚本也不会让积分越滚越多
UPDATE t_user SET points = 2600, total_consume = 2400.00, member_level_id = 4 WHERE id = 1;
UPDATE t_user SET points =  820, total_consume =  860.00, member_level_id = 3 WHERE id = 2;
UPDATE t_user SET points =  180, total_consume =  210.00, member_level_id = 2 WHERE id = 3;
UPDATE t_user SET points =   40, total_consume =   40.00, member_level_id = 1 WHERE id = 4;
UPDATE t_user SET points =    0, total_consume =    0.00, member_level_id = 1 WHERE id = 5;

-- ---------------------------------------------------------------------
-- 4. 重新生成未来 7 天场次：18 个影厅 × 每天 3 场 = 378 条
-- ---------------------------------------------------------------------
INSERT INTO t_schedule (schedule_no, cinema_id, hall_id, movie_id, show_date, start_time, end_time,
                        show_type, lang_type, base_price, seat_total, seat_sold, status)
SELECT CONCAT('S', DATE_FORMAT(d.dt, '%Y%m%d'), LPAD(h.id, 3, '0'), LPAD(sl.slot, 2, '0')),
       h.cinema_id,
       h.id,
       sl.movie_id,
       d.dt,
       TIMESTAMP(d.dt, sl.st),
       TIMESTAMP(d.dt, sl.st) + INTERVAL mv.duration MINUTE,
       CASE WHEN h.hall_type IN (2, 4) THEN 3 WHEN h.hall_type = 3 THEN 2 ELSE 1 END,
       1,
       ROUND(sl.base + h.hall_type * 6, 2),
       h.seat_count,
       0,
       1
FROM t_hall h
         JOIN (SELECT 1 AS slot, 1 AS movie_id, '10:00:00' AS st, 45.00 AS base
               UNION ALL
               SELECT 2, 2, '14:30:00', 42.00
               UNION ALL
               SELECT 3, 3, '19:30:00', 48.00) sl
         JOIN t_movie mv ON mv.id = sl.movie_id
         JOIN (SELECT CURDATE() + INTERVAL 1 DAY AS dt
               UNION ALL SELECT CURDATE() + INTERVAL 2 DAY
               UNION ALL SELECT CURDATE() + INTERVAL 3 DAY
               UNION ALL SELECT CURDATE() + INTERVAL 4 DAY
               UNION ALL SELECT CURDATE() + INTERVAL 5 DAY
               UNION ALL SELECT CURDATE() + INTERVAL 6 DAY
               UNION ALL SELECT CURDATE() + INTERVAL 7 DAY) d
              ON 1 = 1;

-- ---------------------------------------------------------------------
-- 5. 生成 6 笔样例订单
--    先全部以待支付状态插入（由触发器累加 seat_sold），
--    后续再用 UPDATE 触发状态流转，让积分、会员等级、座位释放自动完成。
-- ---------------------------------------------------------------------
-- 注意：t_order 的插入触发器会更新 t_schedule，
--       而这两者不能出现在同一条语句里（MySQL 错误 1442）。
--       所以先把订单参数算好放进临时表，再单独执行 INSERT。
DROP TEMPORARY TABLE IF EXISTS tmp_demo_order;
CREATE TEMPORARY TABLE tmp_demo_order (
    n          INT,
    uid        BIGINT,
    sid        BIGINT,
    qty        TINYINT,
    total      DECIMAL(10,2),
    discount   DECIMAL(10,2),
    pay        DECIMAL(10,2),
    expire_min INT
);

INSERT INTO tmp_demo_order (n, uid, sid, qty, total, discount, pay, expire_min)
SELECT spec.n,
       spec.uid,
       sch.id,
       spec.qty,
       ROUND(sch.base_price * spec.qty, 2),
       ROUND(sch.base_price * spec.qty * 0.08, 2),
       ROUND(sch.base_price * spec.qty * 0.92, 2),
       spec.expire_min
FROM (SELECT 1 AS n, 1 AS uid, 1 AS movie, 1 AS rno, 2 AS qty, 30    AS expire_min
      UNION ALL SELECT 2, 2, 1, 2, 1, 30
      UNION ALL SELECT 3, 3, 2, 1, 3, 30
      UNION ALL SELECT 4, 4, 2, 2, 1, 10080
      UNION ALL SELECT 5, 5, 3, 1, 2, 30
      UNION ALL SELECT 6, 1, 3, 2, 2, 30) spec
         JOIN (SELECT id, movie_id, base_price,
                      ROW_NUMBER() OVER (PARTITION BY movie_id ORDER BY start_time, hall_id) AS rn
               FROM t_schedule) sch
              ON sch.movie_id = spec.movie AND sch.rn = spec.rno;

INSERT INTO t_order (order_no, user_id, schedule_id, ticket_count, total_amount,
                     discount_amount, coupon_amount, points_amount, pay_amount,
                     user_coupon_id, points_used, pay_type, status,
                     pickup_code, expire_time, pay_time, created_at)
SELECT CONCAT('O', DATE_FORMAT(NOW(), '%Y%m%d'), LPAD(n, 3, '0')),
       uid, sid, qty, total, discount, 0.00, 0.00, pay,
       NULL, 0, 1, 0, NULL,
       NOW() + INTERVAL expire_min MINUTE,
       NULL, NOW()
FROM tmp_demo_order
ORDER BY n;

DROP TEMPORARY TABLE tmp_demo_order;

-- 5.1 订单明细：每个订单按购票数量占座（各订单分属不同场次，不会冲突）
INSERT INTO t_order_item (order_id, schedule_id, seat_id, price, discount_share, hold_flag)
SELECT o.id,
       o.schedule_id,
       st.id,
       ROUND(o.total_amount / o.ticket_count, 2),
       ROUND((o.total_amount - o.pay_amount) / o.ticket_count, 2),
       1
FROM t_order o
         JOIN t_schedule sch ON sch.id = o.schedule_id
         JOIN t_seat st ON st.hall_id = sch.hall_id
    AND st.row_no = 2
    AND st.col_no <= o.ticket_count;

-- ---------------------------------------------------------------------
-- 6. 状态流转（触发积分累计、会员升级、座位释放）
-- ---------------------------------------------------------------------
-- 订单 1、2、3：支付成功
UPDATE t_order SET status = 1, pay_time = NOW(), pickup_code = '10000001' WHERE order_no LIKE '%001';
UPDATE t_order SET status = 1, pay_time = NOW(), pickup_code = '20000002' WHERE order_no LIKE '%002';
UPDATE t_order SET status = 1, pay_time = NOW(), pickup_code = '30000003' WHERE order_no LIKE '%003';
-- 订单 3：观影结束，转为已完成
UPDATE t_order SET status = 2 WHERE order_no LIKE '%003';
-- 订单 4：保持待支付（过期时间已设为 7 天后，便于演示锁座流程）
-- 订单 5：用户取消
UPDATE t_order SET status = 3 WHERE order_no LIKE '%005';
-- 订单 6：已支付后申请退票，进入退款中
UPDATE t_order SET status = 1, pay_time = NOW(), pickup_code = '60000006' WHERE order_no LIKE '%006';
UPDATE t_order SET status = 4 WHERE order_no LIKE '%006';

-- 6.1 支付流水
INSERT INTO t_payment (pay_no, order_id, channel, amount, status, trade_no, pay_time)
SELECT CONCAT('P', o.order_no), o.id, 1, o.pay_amount, 1, CONCAT('MOCK', o.order_no), o.pay_time
FROM t_order o
WHERE o.status IN (1, 2, 4);

-- 6.2 退票申请（对应订单 6）
INSERT INTO t_refund (refund_no, order_id, reason, refund_amount, status)
SELECT CONCAT('R', o.order_no), o.id, '临时有事，无法到场', o.pay_amount, 0
FROM t_order o
WHERE o.status = 4;

-- ---------------------------------------------------------------------
-- 7. 评论（触发器会自动回填影片评分）
-- ---------------------------------------------------------------------
INSERT INTO t_comment (user_id, movie_id, order_id, score, content, like_count, status)
SELECT 1, 1, o.id, 5, '特效很震撼，IMAX 厅值回票价。', 12, 1
FROM t_order o WHERE o.order_no LIKE '%001';
INSERT INTO t_comment (user_id, movie_id, order_id, score, content, like_count, status)
SELECT 2, 1, o.id, 4, '剧情中间有点拖，不过画面确实下了功夫。', 5, 1
FROM t_order o WHERE o.order_no LIKE '%002';
INSERT INTO t_comment (user_id, movie_id, order_id, score, content, like_count, status)
SELECT 3, 2, o.id, 5, '国产动画这几年是真的进步了。', 8, 1
FROM t_order o WHERE o.order_no LIKE '%003';
INSERT INTO t_comment (user_id, movie_id, order_id, score, content, like_count, status)
SELECT 4, 2, o.id, 3, '中规中矩，期待下一部。', 1, 0
FROM t_order o WHERE o.order_no LIKE '%004';

-- ---------------------------------------------------------------------
-- 8. 恢复事件
-- ---------------------------------------------------------------------
ALTER EVENT ev_cancel_expired_order ENABLE;

-- ---------------------------------------------------------------------
-- 9. 刷新结果
-- ---------------------------------------------------------------------
SELECT '场次总数' AS 项目, COUNT(*) AS 数量 FROM t_schedule
UNION ALL SELECT '其中可售（未开映）', COUNT(*) FROM t_schedule WHERE start_time > NOW() AND status = 1
UNION ALL SELECT '订单总数', COUNT(*) FROM t_order
UNION ALL SELECT '待支付订单', COUNT(*) FROM t_order WHERE status = 0
UNION ALL SELECT '已支付订单', COUNT(*) FROM t_order WHERE status = 1
UNION ALL SELECT '已完成订单', COUNT(*) FROM t_order WHERE status = 2
UNION ALL SELECT '已取消订单', COUNT(*) FROM t_order WHERE status = 3
UNION ALL SELECT '退款中订单', COUNT(*) FROM t_order WHERE status = 4
UNION ALL SELECT '订单明细', COUNT(*) FROM t_order_item
UNION ALL SELECT '支付记录', COUNT(*) FROM t_payment
UNION ALL SELECT '退票申请', COUNT(*) FROM t_refund
UNION ALL SELECT '评论', COUNT(*) FROM t_comment;

SELECT '最早场次' AS 项目, MIN(start_time) AS 时间 FROM t_schedule
UNION ALL SELECT '最晚场次', MAX(start_time) FROM t_schedule;
