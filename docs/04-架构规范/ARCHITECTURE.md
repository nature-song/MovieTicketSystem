# 架构与开发约定

这份文档定两件事：**代码怎么分层**，以及**以后加功能时按什么步骤做**。定下来是为了避免两种情况：一是模块之间互相调用最后牵一发动全身，二是同一个逻辑在三个地方各写一遍。

改动本文件描述的规则前，先想清楚是否真的必要。

---

## 一、分层与依赖方向

后端五层，**依赖只能向下**：

```
Controller  →  Service  →  Mapper  →  MySQL
   ↑             ↑
   └── 只依赖相邻的下一层，不许跨层 ┘

公共层（common）被所有层使用，但它不依赖任何业务模块
```

对应到物理结构，`common` 与 `module` 是平级的两个包，`common` 里**不允许出现任何业务概念**（不能 import 具体的 `Order`、`Movie`）。

前端同理：

```
views（页面） → stores / api → components
```

页面可以调 api 和 store，组件只接收 props 和事件，组件内部不直接发请求。

---

## 二、后端目录结构

```
backend/src/main/java/com/cinema/
├── CinemaApplication.java
├── common/                      公共基建，不含业务
│   ├── result/                  R<T>、PageResult<T>
│   ├── exception/               BizException、GlobalExceptionHandler
│   ├── constant/                ErrorCode、OrderStatus 等枚举
│   ├── util/                    JwtUtil、PasswordUtil、BizNoGenerator
│   ├── config/                  WebMvcConfig、OpenApiConfig、MybatisConfig
│   └── interceptor/             JwtInterceptor
└── module/                      业务模块，每个模块自成一体
    └── order/                   以订单模块为例
        ├── controller/
        ├── service/
        ├── mapper/
        ├── entity/              与表一一对应
        ├── dto/                 接收前端入参
        └── vo/                  返回给前端
```

**模块之间只允许调用对方的 Service，不允许调用对方的 Mapper。** 这一条是为了以后能把某个模块单独拆出去时不用重写。

---

## 三、前端目录结构

```
frontend/src/
├── api/            每个后端模块对应一个文件，函数只做一次 HTTP 调用
├── router/         路由表 + 登录守卫
├── stores/         Pinia：user、order、booking（临时选座）
├── components/     可复用组件：SeatMap、MovieCard、ScheduleCard
├── views/
│   ├── user/       首页、影片详情、选座、订单、个人中心
│   └── admin/      管理端布局与各管理页
├── utils/          request.ts（Axios 封装）、format.ts
├── styles/         tailwind.css、主题变量
└── assets/
```

页面里**不直接写 URL**，一律从 `api/` 引函数。这样后端改路径时只改一个文件。

---

## 四、六条硬约束

| 编号 | 约束 | 违反后果 |
|---|---|---|
| C-01 | Controller 不得直接注入 Mapper | 业务规则散落，事务边界丢失 |
| C-02 | Service 不得把 Entity 直接返回给前端 | 表结构一变页面就崩 |
| C-03 | Mapper 中不得写业务判断（状态机、库存判断等） | 规则两处维护，必然不一致 |
| C-04 | 跨模块只能调 Service，不得调 Mapper | 模块边界被穿透，无法拆分 |
| C-05 | 所有 SQL 用 `#{}` 参数化，禁止 `${}` 拼接 | SQL 注入 |
| C-06 | 金额、状态一律服务端计算，不采信前端传值 | 改价、越权 |

另外两条与数据库相关：

- **计数器字段（`seat_sold`）只由触发器维护**，Service 层禁止手工修改，否则会重复累加。
- **业务编号（订单号、取票码）唯一索引兜底**，生成时若冲突需重试，不能假设一次成功。

---

## 五、新增一个业务功能：固定七步

以「新增收藏功能」为例，按顺序做，每一步都能单独验证：

1. **定数据**：先想清楚要存哪些字段，会不会影响已有表。优先新建表，不改已有表（见第六节）。
2. **写 SQL**：直接在 MySQL 客户端里把查询/写入语句跑通，确认结果正确。
3. **建实体与 Mapper**：`entity` 对应表，`mapper` 接口方法名与 XML 的 `id` 一致，参数加 `@Param`。
4. **写 Service**：业务判断、事务、异常都放这里，抛出 `BizException(错误码, 提示语)`。
5. **写 DTO / VO**：入参用 DTO 并加校验注解，出参用 VO，不要复用 Entity。
6. **写 Controller**：只做参数接收、调 Service、包 `R<T>`，不写 if-else 业务。
7. **前端接**：`api/` 加函数 → 页面调用 → 处理 loading、空态、错误提示。

**只需要加一个模块的代码，不需要改其他模块。** 如果发现必须改别人模块的代码，先停下来想清楚是不是职责放错了位置。

---

## 六、数据库变更流程

因为数据库脚本是唯一的建库依据，改动必须走脚本，**不能只在 MySQL 客户端里手工改**。

| 变更类型 | 做法 | 是否影响已有数据 |
|---|---|---|
| 加表 | 在 `cinema_booking.sql` 的建表段落追加，同时在 `refresh_demo.sql` 补种子数据 | 否 |
| 加字段 | 在对应 `CREATE TABLE` 中加入；若表已上线，给默认值并允许 NULL | 否 |
| 改字段类型 | 尽量避免。确需修改时评估现有数据能否无损转换 | 可能 |
| 删字段 / 删表 | 先确认代码中无引用，再从脚本移除 | 是 |

**原则：只加不改。** 新增功能通过新增表或新增字段实现，避免破坏已有代码。

---

## 七、接口与版本

- 所有接口以 `/api/v1` 开头。将来若有不兼容改动，新开 `/api/v2`，旧版本保留一段时间。
- 统一响应体：

```json
{ "code": 200, "message": "ok", "data": {} }
```

- 错误码分段：`1xxx` 通用、`2xxx` 认证权限、`3xxx` 业务规则、`4xxx` 参数校验。完整列表见系统设计报告 3.3 节。
- 业务失败不返回 HTTP 500，而是在正常响应里带业务码，前端直接展示 `message`。

---

## 八、命名规范

| 对象 | 规范 | 示例 |
|---|---|---|
| 数据库表 | `t_` + 小写下划线 | `t_order_item` |
| 数据库字段 | 小写下划线 | `pay_amount` |
| Java 类 | 大驼峰 | `OrderService` |
| Java 包 | 全小写 | `com.cinema.module.order` |
| 接口路径 | 小写中划线，名词复数 | `/api/v1/schedules/{id}/seats` |
| 布尔字段 | `is_` 前缀或状态用 `status` | `is_deleted` |
| 前端组件 | 大驼峰，文件名与组件名一致 | `SeatMap.vue` |
| 前端 api 方法 | 动词 + 名词 | `listMovies`、`createOrder` |

---

## 九、什么时候该新建模块

满足下面任意两条，就新建一个 `module/xxx`，而不是塞进现有模块：

- 有独立的数据库主表（而不是别人的附属表）
- 有自己的业务规则与状态流转
- 前端有独立的页面入口
- 预计后续会持续迭代

按当前设计，模块划分为：`auth`、`user`、`movie`、`cinema`、`schedule`、`order`、`stats`。如果以后加「会员活动」或「礼品卡」，直接新增 `promotion`、`giftcard` 模块即可，不需要动 `order` 的内部实现。
