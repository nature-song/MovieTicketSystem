-- =====================================================================
--  影院订票管理系统 · 数据库创建脚本
--  Cinema Booking Management System - DDL / DML
--  MySQL 8.0.44  |  InnoDB  |  utf8mb4
--  学号 8208240230  姓名 宋子谦
--
--  执行方式：
--    "D:\mysql\MySQL Server 8.0\bin\mysql.exe" -u root -p123456 < cinema_booking.sql
--  或在 Workbench 中打开本文件整体执行。
--
--  注意：本脚本第一行会 DROP 同名数据库，重复执行会清空已有数据。
--
--  结构：
--    [1] 建库与设置          [5] 存储过程
--    [2] 建表 16 张          [6] 定时事件
--    [3] 视图 3 个           [7] 测试数据
--    [4] 触发器 4 个         [8] 验证查询
-- =====================================================================

-- ---------------------------------------------------------------------
-- [1] 建库与设置
-- ---------------------------------------------------------------------
DROP DATABASE IF EXISTS cinema_booking;
CREATE DATABASE cinema_booking
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_0900_ai_ci;
USE cinema_booking;

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- [2] 建表
-- ---------------------------------------------------------------------

-- 2.1 会员等级
CREATE TABLE t_member_level (
    id            BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
    level_no      TINYINT       NOT NULL                COMMENT '等级序号 1-5，越大越高',
    level_name    VARCHAR(20)   NOT NULL                COMMENT '等级名称',
    min_consume   DECIMAL(10,2) NOT NULL DEFAULT 0.00   COMMENT '升级所需累计消费（元）',
    discount_rate DECIMAL(3,2)  NOT NULL DEFAULT 1.00   COMMENT '票价折扣率，1.00 表示不打折',
    point_rate    DECIMAL(3,2)  NOT NULL DEFAULT 1.00   COMMENT '积分倍率',
    created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_level_no (level_no),
    CONSTRAINT ck_level_discount CHECK (discount_rate > 0 AND discount_rate <= 1)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '会员等级';

-- 2.2 影院
CREATE TABLE t_cinema (
    id         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    cinema_no  CHAR(10)     NOT NULL                COMMENT '影院业务编号，如 C001',
    name       VARCHAR(60)  NOT NULL                COMMENT '影院名称',
    city       VARCHAR(30)  NOT NULL                COMMENT '所在城市',
    address    VARCHAR(200) NOT NULL                COMMENT '详细地址',
    phone      VARCHAR(20)           DEFAULT NULL   COMMENT '联系电话',
    open_time  TIME         NOT NULL DEFAULT '09:00:00' COMMENT '营业开始时间',
    close_time TIME         NOT NULL DEFAULT '23:59:00' COMMENT '营业结束时间',
    intro      VARCHAR(500)          DEFAULT NULL   COMMENT '影院简介',
    status     TINYINT      NOT NULL DEFAULT 1      COMMENT '1 营业中，0 停业',
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_cinema_no (cinema_no),
    KEY idx_city (city)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '影院';

-- 2.3 影片
CREATE TABLE t_movie (
    id            BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    movie_no      CHAR(12)     NOT NULL                COMMENT '影片业务编号，如 M0001',
    title         VARCHAR(80)  NOT NULL                COMMENT '片名',
    genre         VARCHAR(50)           DEFAULT NULL   COMMENT '类型，多值逗号分隔',
    director      VARCHAR(50)           DEFAULT NULL   COMMENT '导演',
    actors        VARCHAR(255)          DEFAULT NULL   COMMENT '主演',
    country       VARCHAR(50)           DEFAULT NULL   COMMENT '制片国家/地区',
    language      VARCHAR(20)           DEFAULT NULL   COMMENT '语言',
    duration      SMALLINT     NOT NULL                COMMENT '片长（分钟）',
    release_date  DATE         NOT NULL                COMMENT '上映日期',
    offline_date  DATE                  DEFAULT NULL   COMMENT '下映日期',
    intro         TEXT                                 COMMENT '剧情简介',
    poster        VARCHAR(255)          DEFAULT NULL   COMMENT '海报地址',
    avg_score     DECIMAL(3,1) NOT NULL DEFAULT 0.0    COMMENT '平均评分，触发器维护',
    comment_count INT          NOT NULL DEFAULT 0      COMMENT '有效评论数，触发器维护',
    status        TINYINT      NOT NULL DEFAULT 1      COMMENT '1 已上架，0 已下架',
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_movie_no (movie_no),
    KEY idx_status_release (status, release_date),
    KEY idx_title (title),
    CONSTRAINT ck_movie_duration CHECK (duration > 0),
    CONSTRAINT ck_movie_date CHECK (offline_date IS NULL OR offline_date >= release_date)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '影片';

-- 2.4 影厅
CREATE TABLE t_hall (
    id         BIGINT      NOT NULL AUTO_INCREMENT COMMENT '主键',
    cinema_id  BIGINT      NOT NULL                COMMENT '所属影院',
    hall_no    CHAR(6)     NOT NULL                COMMENT '厅号，如 H01',
    name       VARCHAR(30) NOT NULL                COMMENT '影厅名称',
    hall_type  TINYINT     NOT NULL DEFAULT 1      COMMENT '1 普通，2 IMAX，3 3D，4 杜比',
    row_count  SMALLINT    NOT NULL                COMMENT '座位行数',
    col_count  SMALLINT    NOT NULL                COMMENT '座位列数',
    seat_count SMALLINT    NOT NULL                COMMENT '可售座位总数',
    status     TINYINT     NOT NULL DEFAULT 1      COMMENT '1 可用，0 停用',
    created_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_cinema_hall (cinema_id, hall_no),
    KEY idx_cinema (cinema_id),
    CONSTRAINT fk_hall_cinema FOREIGN KEY (cinema_id) REFERENCES t_cinema (id),
    CONSTRAINT ck_hall_size CHECK (row_count > 0 AND col_count > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '影厅';

-- 2.5 座位
CREATE TABLE t_seat (
    id        BIGINT  NOT NULL AUTO_INCREMENT COMMENT '主键',
    hall_id   BIGINT  NOT NULL                COMMENT '所属影厅',
    row_no    TINYINT NOT NULL                COMMENT '行号，从 1 开始',
    col_no    TINYINT NOT NULL                COMMENT '列号，从 1 开始',
    seat_type TINYINT NOT NULL DEFAULT 0      COMMENT '0 普通，1 情侣，2 无障碍',
    status    TINYINT NOT NULL DEFAULT 1      COMMENT '1 可售，0 不可售',
    PRIMARY KEY (id),
    UNIQUE KEY uk_hall_seat (hall_id, row_no, col_no),
    CONSTRAINT fk_seat_hall FOREIGN KEY (hall_id) REFERENCES t_hall (id),
    CONSTRAINT ck_seat_row CHECK (row_no BETWEEN 1 AND 99),
    CONSTRAINT ck_seat_col CHECK (col_no BETWEEN 1 AND 99)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '座位';

-- 2.6 用户
CREATE TABLE t_user (
    id              BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
    user_no         CHAR(12)      NOT NULL                COMMENT '用户业务编号，如 U0000000001',
    phone           CHAR(11)      NOT NULL                COMMENT '手机号，登录账号',
    password        CHAR(64)      NOT NULL                COMMENT 'BCrypt 哈希（$2b$ 开头，60 位）',
    nickname        VARCHAR(30)   NOT NULL                COMMENT '昵称',
    avatar          VARCHAR(255)           DEFAULT NULL   COMMENT '头像地址',
    gender          TINYINT       NOT NULL DEFAULT 0      COMMENT '0 未知，1 男，2 女',
    birthday        DATE                   DEFAULT NULL   COMMENT '生日',
    email           VARCHAR(64)            DEFAULT NULL   COMMENT '邮箱',
    member_level_id BIGINT        NOT NULL                COMMENT '会员等级',
    points          INT           NOT NULL DEFAULT 0      COMMENT '可用积分',
    total_consume   DECIMAL(12,2) NOT NULL DEFAULT 0.00   COMMENT '累计消费（元）',
    status          TINYINT       NOT NULL DEFAULT 1      COMMENT '1 正常，0 冻结',
    created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '注册时间',
    updated_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_user_no (user_no),
    UNIQUE KEY uk_phone (phone),
    KEY idx_member_level (member_level_id),
    CONSTRAINT fk_user_level FOREIGN KEY (member_level_id) REFERENCES t_member_level (id),
    CONSTRAINT ck_user_points CHECK (points >= 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '用户（观众）';

-- 2.7 管理员
CREATE TABLE t_admin (
    id            BIGINT      NOT NULL AUTO_INCREMENT COMMENT '主键',
    username      VARCHAR(30) NOT NULL                COMMENT '登录账号',
    password      CHAR(64)    NOT NULL                COMMENT 'BCrypt 哈希（$2b$ 开头，60 位）',
    real_name     VARCHAR(30) NOT NULL                COMMENT '姓名',
    cinema_id     BIGINT               DEFAULT NULL   COMMENT '所属影院，超级管理员为空',
    role          TINYINT     NOT NULL DEFAULT 1      COMMENT '1 影院管理员，2 超级管理员',
    status        TINYINT     NOT NULL DEFAULT 1      COMMENT '1 正常，0 禁用',
    last_login_at DATETIME             DEFAULT NULL   COMMENT '最后登录时间',
    created_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_admin_username (username),
    KEY idx_admin_cinema (cinema_id),
    CONSTRAINT fk_admin_cinema FOREIGN KEY (cinema_id) REFERENCES t_cinema (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '后台管理员';

-- 2.8 优惠券模板
CREATE TABLE t_coupon (
    id            BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    coupon_no     CHAR(12)     NOT NULL                COMMENT '券模板编号',
    name          VARCHAR(50)  NOT NULL                COMMENT '券名称',
    coupon_type   TINYINT      NOT NULL                COMMENT '1 满减，2 折扣，3 立减',
    face_value    DECIMAL(8,2) NOT NULL DEFAULT 0.00   COMMENT '面额（满减/立减用）',
    discount_rate DECIMAL(3,2)          DEFAULT NULL   COMMENT '折扣率（折扣券用，如 0.90）',
    min_amount    DECIMAL(8,2) NOT NULL DEFAULT 0.00   COMMENT '使用门槛（订单原价下限）',
    valid_start   DATETIME     NOT NULL                COMMENT '有效期开始',
    valid_end     DATETIME     NOT NULL                COMMENT '有效期结束',
    total_qty     INT          NOT NULL DEFAULT 0      COMMENT '发行总量',
    remain_qty    INT          NOT NULL DEFAULT 0      COMMENT '剩余可领数量',
    scope_type    TINYINT      NOT NULL DEFAULT 0      COMMENT '0 全场通用，1 指定影片',
    movie_id      BIGINT                DEFAULT NULL   COMMENT '指定影片（scope_type=1 时有效）',
    status        TINYINT      NOT NULL DEFAULT 1      COMMENT '1 有效，0 停发',
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_coupon_no (coupon_no),
    KEY idx_valid (valid_start, valid_end),
    CONSTRAINT fk_coupon_movie FOREIGN KEY (movie_id) REFERENCES t_movie (id),
    CONSTRAINT ck_coupon_qty CHECK (remain_qty >= 0 AND remain_qty <= total_qty),
    CONSTRAINT ck_coupon_valid CHECK (valid_end > valid_start)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '优惠券模板';

-- 2.9 用户优惠券
CREATE TABLE t_user_coupon (
    id           BIGINT   NOT NULL AUTO_INCREMENT COMMENT '主键',
    user_id      BIGINT   NOT NULL                COMMENT '用户',
    coupon_id    BIGINT   NOT NULL                COMMENT '券模板',
    receive_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '领取时间',
    use_time     DATETIME          DEFAULT NULL   COMMENT '使用时间',
    order_id     BIGINT            DEFAULT NULL   COMMENT '使用时关联订单',
    status       TINYINT  NOT NULL DEFAULT 0      COMMENT '0 未使用，1 已使用，2 已过期',
    PRIMARY KEY (id),
    UNIQUE KEY uk_user_coupon (user_id, coupon_id),
    KEY idx_user_coupon_status (user_id, status),
    CONSTRAINT fk_uc_user FOREIGN KEY (user_id) REFERENCES t_user (id),
    CONSTRAINT fk_uc_coupon FOREIGN KEY (coupon_id) REFERENCES t_coupon (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '用户优惠券';

-- 2.10 场次
CREATE TABLE t_schedule (
    id          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    schedule_no CHAR(20)     NOT NULL                COMMENT '场次业务编号',
    cinema_id   BIGINT       NOT NULL                COMMENT '影院',
    hall_id     BIGINT       NOT NULL                COMMENT '影厅',
    movie_id    BIGINT       NOT NULL                COMMENT '影片',
    show_date   DATE         NOT NULL                COMMENT '放映日期',
    start_time  DATETIME     NOT NULL                COMMENT '开映时间',
    end_time    DATETIME     NOT NULL                COMMENT '散场时间',
    show_type   TINYINT      NOT NULL DEFAULT 1      COMMENT '1 2D，2 3D，3 IMAX，4 杜比',
    lang_type   TINYINT      NOT NULL DEFAULT 1      COMMENT '1 原声，2 配音',
    base_price  DECIMAL(8,2) NOT NULL                COMMENT '基础票价（元）',
    seat_total  SMALLINT     NOT NULL                COMMENT '可售座位数',
    seat_sold   SMALLINT     NOT NULL DEFAULT 0      COMMENT '已占座位数，触发器维护',
    status      TINYINT      NOT NULL DEFAULT 1      COMMENT '1 可售，0 停售，2 已结束',
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_schedule_no (schedule_no),
    KEY idx_hall_start (hall_id, start_time),
    KEY idx_date_status (show_date, status),
    KEY idx_movie_date (movie_id, show_date),
    KEY idx_cinema_date (cinema_id, show_date),
    CONSTRAINT fk_schedule_cinema FOREIGN KEY (cinema_id) REFERENCES t_cinema (id),
    CONSTRAINT fk_schedule_hall FOREIGN KEY (hall_id) REFERENCES t_hall (id),
    CONSTRAINT fk_schedule_movie FOREIGN KEY (movie_id) REFERENCES t_movie (id),
    CONSTRAINT ck_schedule_time CHECK (end_time > start_time),
    CONSTRAINT ck_schedule_seat CHECK (seat_sold >= 0 AND seat_sold <= seat_total)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '场次（排片）';

-- 2.11 订单
CREATE TABLE t_order (
    id              BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
    order_no        CHAR(20)      NOT NULL                COMMENT '订单号，对外唯一编号',
    user_id         BIGINT        NOT NULL                COMMENT '下单用户',
    schedule_id     BIGINT        NOT NULL                COMMENT '场次',
    ticket_count    TINYINT       NOT NULL                COMMENT '购票数量',
    total_amount    DECIMAL(10,2) NOT NULL                COMMENT '原价合计',
    discount_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00   COMMENT '会员折扣减免',
    coupon_amount   DECIMAL(10,2) NOT NULL DEFAULT 0.00   COMMENT '优惠券抵扣',
    points_amount   DECIMAL(10,2) NOT NULL DEFAULT 0.00   COMMENT '积分抵扣',
    pay_amount      DECIMAL(10,2) NOT NULL                COMMENT '实付金额',
    user_coupon_id  BIGINT                 DEFAULT NULL   COMMENT '使用的用户券',
    points_used     INT           NOT NULL DEFAULT 0      COMMENT '消耗积分数',
    pay_type        TINYINT                DEFAULT NULL   COMMENT '1 模拟，2 支付宝，3 微信',
    status          TINYINT       NOT NULL DEFAULT 0      COMMENT '0 待支付，1 已支付，2 已完成，3 已取消，4 退款中，5 已退款',
    pickup_code     CHAR(8)                DEFAULT NULL   COMMENT '取票码，支付成功时生成',
    expire_time     DATETIME      NOT NULL                COMMENT '锁座过期时间',
    pay_time        DATETIME               DEFAULT NULL   COMMENT '支付时间',
    created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '下单时间',
    updated_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_order_no (order_no),
    UNIQUE KEY uk_pickup_code (pickup_code),
    KEY idx_user_time (user_id, created_at),
    KEY idx_status_expire (status, expire_time),
    KEY idx_schedule (schedule_id),
    CONSTRAINT fk_order_user FOREIGN KEY (user_id) REFERENCES t_user (id),
    CONSTRAINT fk_order_schedule FOREIGN KEY (schedule_id) REFERENCES t_schedule (id),
    CONSTRAINT fk_order_uc FOREIGN KEY (user_coupon_id) REFERENCES t_user_coupon (id),
    CONSTRAINT ck_order_count CHECK (ticket_count BETWEEN 1 AND 6),
    CONSTRAINT ck_order_amount CHECK (pay_amount >= 0 AND total_amount >= 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '订单';

-- 2.12 订单明细（同时承担座位占用职能）
CREATE TABLE t_order_item (
    id             BIGINT      NOT NULL AUTO_INCREMENT COMMENT '主键',
    order_id       BIGINT      NOT NULL                COMMENT '所属订单',
    schedule_id    BIGINT      NOT NULL                COMMENT '场次（冗余，用于唯一约束）',
    seat_id        BIGINT      NOT NULL                COMMENT '座位',
    price          DECIMAL(8,2) NOT NULL               COMMENT '座位原价',
    discount_share DECIMAL(8,2) NOT NULL DEFAULT 0.00  COMMENT '该座位分摊的优惠金额',
    hold_flag      TINYINT              DEFAULT 1      COMMENT '1 占用中，NULL 已释放；实现“同场同座唯一”',
    created_at     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_schedule_seat (schedule_id, seat_id, hold_flag),
    KEY idx_order (order_id),
    KEY idx_seat (seat_id),
    CONSTRAINT fk_item_order FOREIGN KEY (order_id) REFERENCES t_order (id),
    CONSTRAINT fk_item_schedule FOREIGN KEY (schedule_id) REFERENCES t_schedule (id),
    CONSTRAINT fk_item_seat FOREIGN KEY (seat_id) REFERENCES t_seat (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '订单明细 / 座位占用';

-- 2.13 支付记录
CREATE TABLE t_payment (
    id         BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
    pay_no     CHAR(24)      NOT NULL                COMMENT '支付流水号',
    order_id   BIGINT        NOT NULL                COMMENT '关联订单',
    channel    TINYINT       NOT NULL DEFAULT 1      COMMENT '1 模拟，2 支付宝，3 微信',
    amount     DECIMAL(10,2) NOT NULL                COMMENT '支付金额',
    status     TINYINT       NOT NULL DEFAULT 0      COMMENT '0 待支付，1 成功，2 失败',
    trade_no   VARCHAR(64)            DEFAULT NULL   COMMENT '第三方交易流水号',
    pay_time   DATETIME               DEFAULT NULL   COMMENT '支付完成时间',
    created_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_pay_no (pay_no),
    KEY idx_order (order_id),
    CONSTRAINT fk_payment_order FOREIGN KEY (order_id) REFERENCES t_order (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '支付记录';

-- 2.14 退票申请
CREATE TABLE t_refund (
    id             BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
    refund_no      CHAR(24)      NOT NULL                COMMENT '退票单号',
    order_id       BIGINT        NOT NULL                COMMENT '关联订单',
    reason         VARCHAR(255)           DEFAULT NULL   COMMENT '退票原因',
    refund_amount  DECIMAL(10,2) NOT NULL                COMMENT '退款金额',
    status         TINYINT       NOT NULL DEFAULT 0      COMMENT '0 待审核，1 通过，2 驳回',
    audit_admin_id BIGINT                 DEFAULT NULL   COMMENT '审核人',
    audit_time     DATETIME               DEFAULT NULL   COMMENT '审核时间',
    audit_remark   VARCHAR(255)           DEFAULT NULL   COMMENT '审核意见',
    created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '申请时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_refund_no (refund_no),
    KEY idx_order (order_id),
    KEY idx_status (status),
    CONSTRAINT fk_refund_order FOREIGN KEY (order_id) REFERENCES t_order (id),
    CONSTRAINT fk_refund_admin FOREIGN KEY (audit_admin_id) REFERENCES t_admin (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '退票申请';

-- 2.15 评论
CREATE TABLE t_comment (
    id         BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
    user_id    BIGINT        NOT NULL                COMMENT '评论用户',
    movie_id   BIGINT        NOT NULL                COMMENT '被评影片',
    order_id   BIGINT                 DEFAULT NULL   COMMENT '对应订单，用于校验已观影',
    score      TINYINT       NOT NULL                COMMENT '评分 1-5 星',
    content    VARCHAR(500)  NOT NULL                COMMENT '评论内容',
    images     VARCHAR(1000)          DEFAULT NULL   COMMENT '图片地址，逗号分隔',
    like_count INT           NOT NULL DEFAULT 0      COMMENT '点赞数',
    status     TINYINT       NOT NULL DEFAULT 0      COMMENT '0 待审核，1 已通过，2 已屏蔽',
    created_at DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '发布时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_user_movie (user_id, movie_id),
    KEY idx_movie_status (movie_id, status),
    CONSTRAINT fk_comment_user FOREIGN KEY (user_id) REFERENCES t_user (id),
    CONSTRAINT fk_comment_movie FOREIGN KEY (movie_id) REFERENCES t_movie (id),
    CONSTRAINT fk_comment_order FOREIGN KEY (order_id) REFERENCES t_order (id),
    CONSTRAINT ck_comment_score CHECK (score BETWEEN 1 AND 5)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '影片评论';

-- 2.16 操作日志
CREATE TABLE t_operation_log (
    id         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    admin_id   BIGINT       NOT NULL                COMMENT '操作管理员',
    op_type    VARCHAR(30)  NOT NULL                COMMENT '操作类型，如 ADD_MOVIE',
    target     VARCHAR(100)          DEFAULT NULL   COMMENT '操作对象',
    content    VARCHAR(500)          DEFAULT NULL   COMMENT '操作内容',
    ip         VARCHAR(45)           DEFAULT NULL   COMMENT '来源 IP',
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '操作时间',
    PRIMARY KEY (id),
    KEY idx_admin_time (admin_id, created_at),
    CONSTRAINT fk_log_admin FOREIGN KEY (admin_id) REFERENCES t_admin (id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '后台操作日志';

-- 2.17 补齐循环外键：用户券 -> 订单
ALTER TABLE t_user_coupon
    ADD CONSTRAINT fk_uc_order FOREIGN KEY (order_id) REFERENCES t_order (id);

-- ---------------------------------------------------------------------
-- [3] 视图
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v_box_office_daily AS
SELECT s.show_date          AS show_date,
       c.id                 AS cinema_id,
       c.name               AS cinema_name,
       m.id                 AS movie_id,
       m.title              AS movie_title,
       COUNT(DISTINCT o.id) AS order_count,
       SUM(o.ticket_count)  AS ticket_count,
       SUM(o.pay_amount)    AS box_office
FROM t_order o
         JOIN t_schedule s ON s.id = o.schedule_id
         JOIN t_cinema c ON c.id = s.cinema_id
         JOIN t_movie m ON m.id = s.movie_id
WHERE o.status IN (1, 2)
GROUP BY s.show_date, c.id, c.name, m.id, m.title;

CREATE OR REPLACE VIEW v_schedule_attendance AS
SELECT s.id                                                  AS schedule_id,
       s.schedule_no                                         AS schedule_no,
       c.name                                                AS cinema_name,
       h.name                                                AS hall_name,
       m.title                                               AS movie_title,
       s.show_date                                           AS show_date,
       s.start_time                                          AS start_time,
       s.seat_total                                          AS seat_total,
       s.seat_sold                                           AS seat_sold,
       ROUND(s.seat_sold * 100.0 / NULLIF(s.seat_total, 0), 2) AS attendance_rate
FROM t_schedule s
         JOIN t_cinema c ON c.id = s.cinema_id
         JOIN t_hall h ON h.id = s.hall_id
         JOIN t_movie m ON m.id = s.movie_id;

CREATE OR REPLACE VIEW v_member_consumption AS
SELECT u.id                     AS user_id,
       u.user_no                AS user_no,
       u.nickname               AS nickname,
       l.level_name             AS level_name,
       COUNT(o.id)              AS paid_order_count,
       IFNULL(SUM(o.pay_amount), 0) AS total_paid,
       IFNULL(ROUND(AVG(o.pay_amount), 2), 0) AS avg_order_amount,
       u.points                 AS points
FROM t_user u
         JOIN t_member_level l ON l.id = u.member_level_id
         LEFT JOIN t_order o ON o.user_id = u.id AND o.status IN (1, 2)
GROUP BY u.id, u.user_no, u.nickname, l.level_name, u.points;

-- ---------------------------------------------------------------------
-- [4] 触发器
--     注意：触发器内不得 UPDATE 触发它的那张表（MySQL 错误 1442），
--           因此订单自身的取票码由应用层在支付时一并写入。
-- ---------------------------------------------------------------------

DELIMITER $$

-- 4.1 订单创建后：累加场次已占座位数
CREATE TRIGGER trg_order_after_insert
    AFTER INSERT ON t_order
    FOR EACH ROW
BEGIN
    UPDATE t_schedule
    SET seat_sold = seat_sold + NEW.ticket_count
    WHERE id = NEW.schedule_id;
END$$

-- 4.2 订单状态变更后：积分累计 + 会员升级 + 座位释放
CREATE TRIGGER trg_order_after_update
    AFTER UPDATE ON t_order
    FOR EACH ROW
BEGIN
    DECLARE v_total DECIMAL(12,2) DEFAULT 0.00;
    DECLARE v_level BIGINT DEFAULT NULL;

    -- (a) 待支付 -> 已支付：累计积分与消费，并自动升级会员
    IF NEW.status = 1 AND OLD.status = 0 THEN
        UPDATE t_user
        SET points        = points + FLOOR(NEW.pay_amount),
            total_consume = total_consume + NEW.pay_amount
        WHERE id = NEW.user_id;

        SELECT total_consume INTO v_total FROM t_user WHERE id = NEW.user_id;

        SELECT id INTO v_level
        FROM t_member_level
        WHERE min_consume <= v_total
        ORDER BY level_no DESC
        LIMIT 1;

        IF v_level IS NOT NULL THEN
            UPDATE t_user SET member_level_id = v_level WHERE id = NEW.user_id;
        END IF;
    END IF;

    -- (b) 待支付 -> 已取消：释放座位
    IF NEW.status = 3 AND OLD.status = 0 THEN
        UPDATE t_order_item SET hold_flag = NULL
        WHERE order_id = NEW.id AND hold_flag IS NOT NULL;

        UPDATE t_schedule
        SET seat_sold = GREATEST(seat_sold - NEW.ticket_count, 0)
        WHERE id = NEW.schedule_id;
    END IF;

    -- (c) 已支付/退款中 -> 已退款：释放座位
    IF NEW.status = 5 AND OLD.status IN (1, 4) THEN
        UPDATE t_order_item SET hold_flag = NULL
        WHERE order_id = NEW.id AND hold_flag IS NOT NULL;

        UPDATE t_schedule
        SET seat_sold = GREATEST(seat_sold - NEW.ticket_count, 0)
        WHERE id = NEW.schedule_id;
    END IF;
END$$

-- 4.3 评论新增后：重算影片平均分与评论数
CREATE TRIGGER trg_comment_after_insert
    AFTER INSERT ON t_comment
    FOR EACH ROW
BEGIN
    UPDATE t_movie m
    SET m.comment_count = (SELECT COUNT(*) FROM t_comment c
                           WHERE c.movie_id = NEW.movie_id AND c.status = 1),
        m.avg_score     = IFNULL((SELECT ROUND(AVG(c.score), 1) FROM t_comment c
                                  WHERE c.movie_id = NEW.movie_id AND c.status = 1), 0.0)
    WHERE m.id = NEW.movie_id;
END$$

-- 4.4 评论审核状态或评分变更后：重算
CREATE TRIGGER trg_comment_after_update
    AFTER UPDATE ON t_comment
    FOR EACH ROW
BEGIN
    IF NOT (NEW.status <=> OLD.status) OR NOT (NEW.score <=> OLD.score) THEN
        UPDATE t_movie m
        SET m.comment_count = (SELECT COUNT(*) FROM t_comment c
                               WHERE c.movie_id = NEW.movie_id AND c.status = 1),
            m.avg_score     = IFNULL((SELECT ROUND(AVG(c.score), 1) FROM t_comment c
                                      WHERE c.movie_id = NEW.movie_id AND c.status = 1), 0.0)
        WHERE m.id = NEW.movie_id;
    END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- [5] 存储过程
-- ---------------------------------------------------------------------

DELIMITER $$

-- 5.1 退票审核
CREATE PROCEDURE sp_audit_refund(
    IN p_refund_id BIGINT,
    IN p_admin_id BIGINT,
    IN p_result TINYINT,
    IN p_remark VARCHAR(255),
    OUT p_code INT,
    OUT p_msg VARCHAR(100)
)
BEGIN
    DECLARE v_order_id BIGINT DEFAULT NULL;
    DECLARE v_status TINYINT DEFAULT NULL;
    DECLARE v_user_id BIGINT DEFAULT NULL;
    DECLARE v_uc_id BIGINT DEFAULT NULL;
    DECLARE v_points INT DEFAULT 0;
    DECLARE v_order_status TINYINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            ROLLBACK;
            SET p_code = 500;
            SET p_msg = '退票审核失败，事务已回滚';
        END;

    START TRANSACTION;

    SELECT order_id, status INTO v_order_id, v_status
    FROM t_refund WHERE id = p_refund_id FOR UPDATE;

    IF v_order_id IS NULL THEN
        ROLLBACK;
        SET p_code = 404; SET p_msg = '退票申请不存在';
    ELSEIF v_status <> 0 THEN
        ROLLBACK;
        SET p_code = 409; SET p_msg = '该申请已审核，请勿重复操作';
    ELSE
        SELECT user_id, user_coupon_id, points_used, status
        INTO v_user_id, v_uc_id, v_points, v_order_status
        FROM t_order WHERE id = v_order_id FOR UPDATE;

        IF v_order_status <> 4 THEN
            ROLLBACK;
            SET p_code = 409; SET p_msg = '订单不在退款中状态';
        ELSEIF p_result = 1 THEN
            UPDATE t_refund
            SET status = 1, audit_admin_id = p_admin_id,
                audit_time = NOW(), audit_remark = p_remark
            WHERE id = p_refund_id;

            -- 触发器会释放座位并回退 seat_sold
            UPDATE t_order SET status = 5 WHERE id = v_order_id;

            IF v_uc_id IS NOT NULL THEN
                UPDATE t_user_coupon
                SET status = 0, use_time = NULL, order_id = NULL
                WHERE id = v_uc_id;
            END IF;

            IF v_points > 0 THEN
                UPDATE t_user SET points = points + v_points WHERE id = v_user_id;
            END IF;

            COMMIT;
            SET p_code = 200; SET p_msg = '审核通过，已退款';
        ELSE
            UPDATE t_refund
            SET status = 2, audit_admin_id = p_admin_id,
                audit_time = NOW(), audit_remark = p_remark
            WHERE id = p_refund_id;

            UPDATE t_order SET status = 1 WHERE id = v_order_id;

            COMMIT;
            SET p_code = 200; SET p_msg = '已驳回，订单恢复为已支付';
        END IF;
    END IF;
END$$

-- 5.2 批量排片
CREATE PROCEDURE sp_generate_schedules(
    IN p_cinema_id BIGINT,
    IN p_hall_id BIGINT,
    IN p_movie_id BIGINT,
    IN p_start_date DATE,
    IN p_end_date DATE,
    IN p_first_start TIME,
    IN p_per_day INT,
    IN p_interval_min INT,
    IN p_price DECIMAL(8,2),
    IN p_show_type TINYINT,
    IN p_lang_type TINYINT,
    OUT p_created INT,
    OUT p_code INT,
    OUT p_msg VARCHAR(100)
)
BEGIN
    DECLARE v_days INT DEFAULT 0;
    DECLARE v_i INT DEFAULT 0;
    DECLARE v_j INT DEFAULT 0;
    DECLARE v_cur_date DATE;
    DECLARE v_start DATETIME;
    DECLARE v_end DATETIME;
    DECLARE v_duration INT DEFAULT 0;
    DECLARE v_seat_total SMALLINT DEFAULT 0;
    DECLARE v_conflict INT DEFAULT 0;
    DECLARE v_abort TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            ROLLBACK;
            SET p_created = 0;
            SET p_code = 500;
            SET p_msg = '批量排片失败，事务已回滚';
        END;

    SET p_created = 0;

    SELECT duration INTO v_duration FROM t_movie WHERE id = p_movie_id;
    SELECT seat_count INTO v_seat_total FROM t_hall WHERE id = p_hall_id;

    IF v_duration IS NULL OR v_duration = 0 OR v_seat_total = 0 THEN
        SET p_code = 404;
        SET p_msg = '影片或影厅不存在';
    ELSE
        START TRANSACTION;
        SET v_days = DATEDIFF(p_end_date, p_start_date) + 1;

        WHILE v_i < v_days AND v_abort = 0 DO
                SET v_cur_date = DATE_ADD(p_start_date, INTERVAL v_i DAY);
                SET v_j = 0;

                WHILE v_j < p_per_day AND v_abort = 0 DO
                        SET v_start = TIMESTAMP(v_cur_date, p_first_start)
                            + INTERVAL (v_j * (v_duration + p_interval_min)) MINUTE;
                        SET v_end = v_start + INTERVAL v_duration MINUTE;

                        SELECT COUNT(*) INTO v_conflict
                        FROM t_schedule
                        WHERE hall_id = p_hall_id
                          AND start_time < v_end + INTERVAL 15 MINUTE
                          AND end_time + INTERVAL 15 MINUTE > v_start;

                        IF v_conflict > 0 THEN
                            ROLLBACK;
                            SET v_abort = 1;
                            SET p_created = 0;
                            SET p_code = 409;
                            SET p_msg = CONCAT('时间冲突：',
                                               DATE_FORMAT(v_start, '%Y-%m-%d %H:%i'));
                        ELSE
                            INSERT INTO t_schedule (schedule_no, cinema_id, hall_id, movie_id,
                                                    show_date, start_time, end_time,
                                                    show_type, lang_type, base_price,
                                                    seat_total, seat_sold, status)
                            VALUES (CONCAT('S', DATE_FORMAT(v_start, '%Y%m%d%H%i'),
                                           LPAD(p_hall_id, 3, '0')),
                                    p_cinema_id, p_hall_id, p_movie_id,
                                    v_cur_date, v_start, v_end,
                                    p_show_type, p_lang_type, p_price,
                                    v_seat_total, 0, 1);
                            SET p_created = p_created + 1;
                            SET v_j = v_j + 1;
                        END IF;
                    END WHILE;
                SET v_i = v_i + 1;
            END WHILE;

        IF v_abort = 0 THEN
            COMMIT;
            SET p_code = 200;
            SET p_msg = CONCAT('成功生成 ', p_created, ' 个场次');
        END IF;
    END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- [6] 定时事件：锁座超时自动取消
--     若 SET GLOBAL 无权限，可改由 Spring 的 @Scheduled 完成同样逻辑。
-- ---------------------------------------------------------------------
SET GLOBAL event_scheduler = ON;

DELIMITER $$
CREATE EVENT IF NOT EXISTS ev_cancel_expired_order
    ON SCHEDULE EVERY 1 MINUTE
        STARTS CURRENT_TIMESTAMP
    DO
    BEGIN
        UPDATE t_order SET status = 3
        WHERE status = 0 AND expire_time < NOW();
    END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- [7] 测试数据
-- ---------------------------------------------------------------------

INSERT INTO t_member_level (level_no, level_name, min_consume, discount_rate, point_rate) VALUES
    (1, '普通会员', 0.00,   1.00, 1.00),
    (2, '银卡会员', 200.00, 0.98, 1.20),
    (3, '金卡会员', 800.00, 0.95, 1.50),
    (4, '白金会员', 2000.00, 0.92, 1.80),
    (5, '钻石会员', 5000.00, 0.88, 2.00);

INSERT INTO t_cinema (cinema_no, name, city, address, phone, open_time, close_time, intro, status) VALUES
    ('C001', '星轶影城（中山路店）', '杭州', '杭州市西湖区中山路 88 号 5 层', '0571-88001001', '09:00:00', '23:00:00', '品牌旗舰店，配置 IMAX 与杜比全景声厅', 1),
    ('C002', '星轶影城（滨江店）',   '杭州', '杭州市滨江区江南大道 200 号 3 层', '0571-88001002', '09:30:00', '23:30:00', '社区型影城，适合亲子观影', 1),
    ('C003', '星轶影城（余杭店）',   '杭州', '杭州市余杭区文一西路 66 号 4 层', '0571-88001003', '10:00:00', '23:00:00', '新开影院，全激光放映', 1);

INSERT INTO t_hall (cinema_id, hall_no, name, hall_type, row_count, col_count, seat_count, status) VALUES
    (1, 'H01', '1 号 IMAX 厅', 2, 12, 16, 192, 1),
    (1, 'H02', '2 号杜比厅',   4, 10, 14, 140, 1),
    (1, 'H03', '3 号 3D 厅',   3, 10, 12, 120, 1),
    (1, 'H04', '4 号标准厅',   1,  9, 12, 108, 1),
    (1, 'H05', '5 号标准厅',   1,  9, 12, 108, 1),
    (1, 'H06', '6 号标准厅',   1,  8, 10,  80, 1),
    (2, 'H01', '1 号 3D 厅',   3, 10, 12, 120, 1),
    (2, 'H02', '2 号标准厅',   1,  9, 12, 108, 1),
    (2, 'H03', '3 号标准厅',   1,  9, 12, 108, 1),
    (2, 'H04', '4 号标准厅',   1,  8, 10,  80, 1),
    (2, 'H05', '5 号小厅',     1,  6, 10,  60, 1),
    (2, 'H06', '6 号小厅',     1,  6, 10,  60, 1),
    (3, 'H01', '1 号杜比厅',   4, 10, 14, 140, 1),
    (3, 'H02', '2 号标准厅',   1,  9, 12, 108, 1),
    (3, 'H03', '3 号标准厅',   1,  9, 12, 108, 1),
    (3, 'H04', '4 号标准厅',   1,  8, 12,  96, 1),
    (3, 'H05', '5 号标准厅',   1,  8, 12,  96, 1),
    (3, 'H06', '6 号小厅',     1,  6,  8,  48, 1);

-- 7.4 座位：用 1-20 的数字表按行列批量生成
--     注意：MySQL 不允许在同一条语句中两次引用同一张临时表（错误 1137），
--     因此这里建两张内容相同、名字不同的临时表分别充当行号与列号。
CREATE TEMPORARY TABLE tmp_row (n INT PRIMARY KEY);
CREATE TEMPORARY TABLE tmp_col (n INT PRIMARY KEY);
INSERT INTO tmp_row (n) VALUES
    (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),
    (11),(12),(13),(14),(15),(16),(17),(18),(19),(20);
INSERT INTO tmp_col (n) SELECT n FROM tmp_row;

INSERT INTO t_seat (hall_id, row_no, col_no, seat_type, status)
SELECT h.id, r.n, c.n,
       CASE
           WHEN r.n = h.row_count AND h.row_count >= 8 AND c.n IN (4, 5) THEN 2
           WHEN r.n = 5 AND h.row_count >= 5 AND c.n IN (4, 5) AND h.col_count >= 5 THEN 1
           ELSE 0
           END,
       1
FROM t_hall h
         JOIN tmp_row r ON r.n <= h.row_count
         JOIN tmp_col c ON c.n <= h.col_count;

DROP TEMPORARY TABLE tmp_row;
DROP TEMPORARY TABLE tmp_col;

INSERT INTO t_movie (movie_no, title, genre, director, actors, country, language, duration,
                     release_date, offline_date, intro, avg_score, comment_count, status) VALUES
    ('M0001', '流浪地球 3', '科幻,冒险', '郭帆', '吴京,刘德华,李雪健', '中国', '国语', 168, '2026-10-01', '2026-12-31', '太阳危机迫近，人类启动移山计划。', 0.0, 0, 1),
    ('M0002', '长安三万里 2', '动画,历史', '谢君伟', '杨天翔,凌振赫', '中国', '国语', 152, '2026-10-15', '2026-12-15', '高适与李白的人生际遇。', 0.0, 0, 1),
    ('M0003', '碟中谍 8', '动作,谍战', '克里斯托弗·麦奎里', '汤姆·克鲁斯', '美国', '英语', 156, '2026-10-20', '2026-12-20', '伊森小队再战不可能任务。', 0.0, 0, 1),
    ('M0004', '深海奇缘', '动画,家庭', '田晓鹏', '—', '中国', '国语', 108, '2026-11-01', '2027-01-10', '一场关于勇气与成长的深海冒险。', 0.0, 0, 1),
    ('M0005', '无名之辈 2', '剧情,喜剧', '饶晓志', '陈建斌,章宇', '中国', '国语', 122, '2026-11-08', '2027-01-20', '小人物的悲喜交集。', 0.0, 0, 1),
    ('M0006', '星际穿越（重映）', '科幻,剧情', '克里斯托弗·诺兰', '马修·麦康纳', '美国', '英语', 169, '2026-09-01', '2026-11-30', '经典重映，穿越虫洞寻找新家园。', 0.0, 0, 1),
    ('M0007', '功夫熊猫 4', '动画,喜剧', '迈克·米切尔', '—', '美国', '国语', 94, '2026-11-15', '2027-02-01', '阿宝开启新的修行之旅。', 0.0, 0, 0),
    ('M0008', '明日战记', '科幻,动作', '吴炫辉', '古天乐,刘青云', '中国', '国语', 99, '2026-12-01', '2027-03-01', '未来战场上的机甲对决。', 0.0, 0, 0);

-- 演示账号密码：用户 123456，管理员 admin123（下列为对应的 BCrypt 哈希，可直接登录）
INSERT INTO t_user (user_no, phone, password, nickname, gender, member_level_id, points, total_consume, status) VALUES
    ('U0000000001', '13800000001', '$2b$10$X/s2ZXvjqcizhGjp3o33b.7KleOtJyzC3wadyy43VKZLMemLsGjl6', '张小满', 1, 4, 2600, 2400.00, 1),
    ('U0000000002', '13800000002', '$2b$10$X/s2ZXvjqcizhGjp3o33b.7KleOtJyzC3wadyy43VKZLMemLsGjl6', '李思远', 2, 3,  820,  860.00, 1),
    ('U0000000003', '13800000003', '$2b$10$X/s2ZXvjqcizhGjp3o33b.7KleOtJyzC3wadyy43VKZLMemLsGjl6', '王浩然', 1, 2,  180,  210.00, 1),
    ('U0000000004', '13800000004', '$2b$10$X/s2ZXvjqcizhGjp3o33b.7KleOtJyzC3wadyy43VKZLMemLsGjl6', '赵一鸣', 1, 1,   40,   40.00, 1),
    ('U0000000005', '13800000005', '$2b$10$X/s2ZXvjqcizhGjp3o33b.7KleOtJyzC3wadyy43VKZLMemLsGjl6', '陈可欣', 2, 1,    0,    0.00, 1);

INSERT INTO t_admin (username, password, real_name, cinema_id, role, status) VALUES
    ('admin',    '$2b$10$0xX4/aK9fy6wuJZnoqgOW.KsfdxgFXHVdPV/cuKL7Mgq4k6AZwNb.', '超级管理员',   NULL, 2, 1),
    ('cinema01', '$2b$10$0xX4/aK9fy6wuJZnoqgOW.KsfdxgFXHVdPV/cuKL7Mgq4k6AZwNb.', '中山路店-店长', 1,   1, 1),
    ('cinema02', '$2b$10$0xX4/aK9fy6wuJZnoqgOW.KsfdxgFXHVdPV/cuKL7Mgq4k6AZwNb.', '滨江店-店长',   2,   1, 1),
    ('cinema03', '$2b$10$0xX4/aK9fy6wuJZnoqgOW.KsfdxgFXHVdPV/cuKL7Mgq4k6AZwNb.', '余杭店-店长',   3,   1, 1);

INSERT INTO t_coupon (coupon_no, name, coupon_type, face_value, discount_rate, min_amount,
                      valid_start, valid_end, total_qty, remain_qty, scope_type, movie_id, status) VALUES
    ('CP0000000001', '全场满 50 减 10',  1, 10.00, NULL, 50.00,  '2026-11-01 00:00:00', '2027-03-31 23:59:59', 1000, 1000, 0, NULL, 1),
    ('CP0000000002', '全场满 100 减 25', 1, 25.00, NULL, 100.00, '2026-11-01 00:00:00', '2027-03-31 23:59:59',  500,  500, 0, NULL, 1),
    ('CP0000000003', '科幻片 9 折券',    2,  0.00, 0.90,  0.00,  '2026-11-01 00:00:00', '2026-12-31 23:59:59',  300,  300, 1, 1,    1),
    ('CP0000000004', '新用户立减 5 元',  3,  5.00, NULL,  0.00,  '2026-11-01 00:00:00', '2027-06-30 23:59:59', 2000, 2000, 0, NULL, 1);

INSERT INTO t_user_coupon (user_id, coupon_id, status) VALUES
    (1, 1, 0), (1, 2, 0), (1, 3, 0),
    (2, 1, 0), (2, 4, 0),
    (3, 4, 0),
    (4, 1, 0), (5, 1, 0);

-- 7.10 场次：按执行当天为基准，生成未来 7 天、每个影厅每天 3 个时段
--      这样无论哪天执行脚本，都有可售场次；若隔一段时间数据过期，运行 refresh_demo.sql 即可刷新
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

-- 7.11 订单：先全部以待支付状态插入，再由 UPDATE 触发状态流转，
--      这样积分累计、座位计数、座位释放都由触发器自动完成，数据自然一致。
INSERT INTO t_order (order_no, user_id, schedule_id, ticket_count, total_amount, discount_amount,
                     coupon_amount, points_amount, pay_amount, user_coupon_id, points_used,
                     pay_type, status, expire_time, pay_time, created_at) VALUES
    ('O202611160930001', 1, 1, 2, 90.00,  7.20, 10.00, 0.00, 72.80,  1,  0, 1, 0, NOW() + INTERVAL 15 MINUTE, NULL, NOW()),
    ('O202611161015002', 2, 2, 1, 45.00,  0.90,  0.00, 0.00, 44.10,  NULL, 0, 1, 0, NOW() + INTERVAL 15 MINUTE, NULL, NOW()),
    ('O202611161130003', 3, 3, 3, 138.00, 2.76,  0.00, 0.00, 135.24, NULL, 0, 1, 0, NOW() + INTERVAL 15 MINUTE, NULL, NOW()),
    ('O202611161400004', 4, 4, 1, 45.00,  0.00,  0.00, 0.00, 45.00,  NULL, 0, NULL, 0, NOW() + INTERVAL 15 MINUTE, NULL, NOW()),
    ('O202611161500005', 5, 5, 2, 84.00,  0.00,  0.00, 0.00, 84.00,  NULL, 0, NULL, 0, NOW() + INTERVAL 15 MINUTE, NULL, NOW());

-- 7.12 订单明细：每个订单按购票数量占座
INSERT INTO t_order_item (order_id, schedule_id, seat_id, price, discount_share, hold_flag)
SELECT o.id,
       o.schedule_id,
       seat.id,
       ROUND(o.total_amount / o.ticket_count, 2),
       ROUND((o.total_amount - o.pay_amount) / o.ticket_count, 2),
       1
FROM t_order o
         JOIN t_schedule sch ON sch.id = o.schedule_id
         JOIN t_seat seat ON seat.hall_id = sch.hall_id
    AND seat.row_no = 2
    AND seat.col_no <= o.ticket_count
WHERE o.id IN (1, 2, 3, 4, 5);

-- 7.13 状态流转（触发触发器）
UPDATE t_order SET status = 1, pay_time = NOW(), pickup_code = '12345678'
WHERE id = 1;
UPDATE t_order SET status = 1, pay_time = NOW(), pickup_code = '22345678'
WHERE id = 2;
UPDATE t_order SET status = 1, pay_time = NOW(), pickup_code = '32345678'
WHERE id = 3;
-- 订单 4 保持待支付；订单 5 模拟超时取消
UPDATE t_order SET status = 3 WHERE id = 5;

-- 7.14 支付记录
INSERT INTO t_payment (pay_no, order_id, channel, amount, status, trade_no, pay_time) VALUES
    ('P202611160930001', 1, 1, 72.80,  1, 'MOCK202611160930001', NOW()),
    ('P202611161015002', 2, 1, 44.10,  1, 'MOCK202611161015002', NOW()),
    ('P202611161130003', 3, 1, 135.24, 1, 'MOCK202611161130003', NOW());

-- 7.15 评论（触发器会据此回填影片评分）
INSERT INTO t_comment (user_id, movie_id, order_id, score, content, like_count, status) VALUES
    (1, 1, 1, 5, '特效震撼，IMAX 值回票价。', 12, 1),
    (2, 2, 2, 4, '剧情略拖，但画面确实不错。', 5, 1),
    (3, 3, 3, 5, '动作场面干净利落，推荐。', 8, 1),
    (4, 1, 4, 3, '中规中矩，期待下一部。', 1, 0);

-- ---------------------------------------------------------------------
-- [8] 验证查询
-- ---------------------------------------------------------------------
SELECT '影院' AS 对象, COUNT(*) AS 记录数 FROM t_cinema
UNION ALL SELECT '影厅',   COUNT(*) FROM t_hall
UNION ALL SELECT '座位',   COUNT(*) FROM t_seat
UNION ALL SELECT '影片',   COUNT(*) FROM t_movie
UNION ALL SELECT '场次',   COUNT(*) FROM t_schedule
UNION ALL SELECT '用户',   COUNT(*) FROM t_user
UNION ALL SELECT '订单',   COUNT(*) FROM t_order
UNION ALL SELECT '订单明细', COUNT(*) FROM t_order_item
UNION ALL SELECT '支付记录', COUNT(*) FROM t_payment
UNION ALL SELECT '评论',   COUNT(*) FROM t_comment;

-- 验证 1：同场同座是否存在重复占用（应返回空集）
SELECT schedule_id, seat_id, COUNT(*) AS cnt
FROM t_order_item
WHERE hold_flag = 1
GROUP BY schedule_id, seat_id
HAVING cnt > 1;

-- 验证 2：触发器是否回填了影片评分
SELECT id, title, comment_count, avg_score FROM t_movie WHERE comment_count > 0;

-- 验证 3：场次上座率
SELECT * FROM v_schedule_attendance WHERE seat_sold > 0
ORDER BY show_date, start_time LIMIT 10;

-- 验证 4：日票房
SELECT * FROM v_box_office_daily ORDER BY box_office DESC LIMIT 10;

-- 验证 5：会员消费
SELECT * FROM v_member_consumption ORDER BY total_paid DESC;
