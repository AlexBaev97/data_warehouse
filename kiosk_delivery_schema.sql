-- =====================================================================
-- База данных: «Поставки товаров в систему розничных киосков»
-- СУБД: PostgreSQL
-- Модель данных: третья нормальная форма (3НФ)
-- =====================================================================
-- Предметная область: сеть розничных киосков заказывает товары у
-- поставщиков. Документ поставки (delivery) фиксирует, какой товар,
-- в каком количестве и по какой цене поставляется в конкретный киоск.
-- После приёмки поставки остатки товара в киоске (kiosk_stock) меняются.
-- =====================================================================

-- Сброс таблиц (в порядке, обратном зависимостям) для повторного запуска
DROP TABLE IF EXISTS kiosk_stock;
DROP TABLE IF EXISTS delivery_item;
DROP TABLE IF EXISTS delivery;
DROP TABLE IF EXISTS employee;
DROP TABLE IF EXISTS kiosk;
DROP TABLE IF EXISTS product;
DROP TABLE IF EXISTS supplier;
DROP TABLE IF EXISTS category;

-- ---------------------------------------------------------------------
-- 1. category — категория товара (справочник)
-- Вынесена отдельно, чтобы убрать транзитивную зависимость:
-- «название категории» зависело бы от «id категории», а не от ключа товара.
-- ---------------------------------------------------------------------
CREATE TABLE category (
    category_id SERIAL       PRIMARY KEY,      -- первичный ключ (PK)
    name        VARCHAR(100) NOT NULL UNIQUE   -- наименование категории
);

COMMENT ON TABLE  category             IS 'Справочник категорий товаров';
COMMENT ON COLUMN category.category_id IS 'Идентификатор категории (PK)';
COMMENT ON COLUMN category.name        IS 'Наименование категории (уникально)';

-- ---------------------------------------------------------------------
-- 2. product — товар
-- Каждый атрибут зависит только от ключа товара (product_id).
-- category_id — внешний ключ вместо дублирования названия категории.
-- ---------------------------------------------------------------------
CREATE TABLE product (
    product_id     SERIAL        PRIMARY KEY,                -- PK
    name           VARCHAR(200)  NOT NULL,                   -- наименование товара
    sku            VARCHAR(50)   NOT NULL UNIQUE,            -- артикул (SKU)
    barcode        VARCHAR(50)   UNIQUE,                     -- штрихкод EAN-13
    unit           VARCHAR(20)   NOT NULL DEFAULT 'шт',      -- единица измерения (шт/кг/л)
    purchase_price NUMERIC(12,2) NOT NULL CHECK (purchase_price >= 0), -- закупочная цена
    retail_price   NUMERIC(12,2) NOT NULL CHECK (retail_price >= 0),   -- розничная цена
    category_id    INT           NOT NULL REFERENCES category(category_id) -- FK на категорию
);

COMMENT ON TABLE  product               IS 'Справочник товаров';
COMMENT ON COLUMN product.product_id    IS 'Идентификатор товара (PK)';
COMMENT ON COLUMN product.sku           IS 'Артикул (уникальный)';
COMMENT ON COLUMN product.category_id   IS 'Ссылка на категорию (FK -> category)';

-- ---------------------------------------------------------------------
-- 3. supplier — поставщик
-- ---------------------------------------------------------------------
CREATE TABLE supplier (
    supplier_id    SERIAL        PRIMARY KEY,        -- PK
    name           VARCHAR(200)  NOT NULL,           -- наименование поставщика
    inn            VARCHAR(12)   UNIQUE,             -- ИНН организации
    address        VARCHAR(300),                     -- юридический адрес
    contact_person VARCHAR(150),                     -- контактное лицо
    phone          VARCHAR(30)                       -- телефон
);

COMMENT ON TABLE  supplier              IS 'Справочник поставщиков';
COMMENT ON COLUMN supplier.supplier_id  IS 'Идентификатор поставщика (PK)';
COMMENT ON COLUMN supplier.inn          IS 'ИНН (уникальный)';

-- ---------------------------------------------------------------------
-- 4. kiosk — розничный киоск (точка приёмки товара)
-- ---------------------------------------------------------------------
CREATE TABLE kiosk (
    kiosk_id   SERIAL       PRIMARY KEY,        -- PK
    name       VARCHAR(100) NOT NULL,           -- наименование киоска
    address    VARCHAR(300) NOT NULL,           -- адрес расположения
    phone      VARCHAR(30),                     -- телефон
    open_time  TIME,                            -- время открытия
    close_time TIME                             -- время закрытия
);

COMMENT ON TABLE  kiosk           IS 'Справочник розничных киосков';
COMMENT ON COLUMN kiosk.kiosk_id  IS 'Идентификатор киоска (PK)';

-- ---------------------------------------------------------------------
-- 5. employee — сотрудник (продавец/менеджер киоска)
-- kiosk_id — внешний ключ: сотрудник закреплён за конкретным киоском.
-- ---------------------------------------------------------------------
CREATE TABLE employee (
    employee_id SERIAL       PRIMARY KEY,            -- PK
    full_name   VARCHAR(150) NOT NULL,               -- ФИО сотрудника
    position    VARCHAR(100),                        -- должность
    phone       VARCHAR(30),                         -- телефон
    kiosk_id    INT          REFERENCES kiosk(kiosk_id) -- FK: киоск, где работает
);

COMMENT ON TABLE  employee             IS 'Справочник сотрудников киосков';
COMMENT ON COLUMN employee.employee_id IS 'Идентификатор сотрудника (PK)';
COMMENT ON COLUMN employee.kiosk_id    IS 'Киоск, за которым закреплён сотрудник (FK)';

-- ---------------------------------------------------------------------
-- 6. delivery — поставка (заголовок документа поставки)
-- Хранит только ссылки (FK) на киоск, поставщика и сотрудника, а не их
-- названия — это и есть устранение транзитивной зависимости (3НФ).
-- ---------------------------------------------------------------------
CREATE TABLE delivery (
    delivery_id            SERIAL       PRIMARY KEY,                 -- PK
    delivery_number        VARCHAR(50)  NOT NULL UNIQUE,             -- номер накладной
    delivery_date          DATE         NOT NULL,                    -- дата поставки
    kiosk_id               INT          NOT NULL REFERENCES kiosk(kiosk_id),        -- куда поставляют
    supplier_id            INT          NOT NULL REFERENCES supplier(supplier_id),  -- кто поставляет
    responsible_employee_id INT         REFERENCES employee(employee_id),           -- кто оформил
    status                 VARCHAR(20)  NOT NULL DEFAULT 'created'   -- статус документа
        CHECK (status IN ('created','confirmed','shipped','received','cancelled')),
    comment                TEXT                                      -- примечание
);

COMMENT ON TABLE  delivery                     IS 'Документ поставки (заголовок)';
COMMENT ON COLUMN delivery.delivery_id         IS 'Идентификатор поставки (PK)';
COMMENT ON COLUMN delivery.delivery_number     IS 'Номер накладной (уникальный)';
COMMENT ON COLUMN delivery.kiosk_id            IS 'Киоск-получатель (FK -> kiosk)';
COMMENT ON COLUMN delivery.supplier_id         IS 'Поставщик (FK -> supplier)';
COMMENT ON COLUMN delivery.responsible_employee_id IS 'Оформивший сотрудник (FK -> employee)';
COMMENT ON COLUMN delivery.status              IS 'Статус: created/confirmed/shipped/received/cancelled';

-- ---------------------------------------------------------------------
-- 7. delivery_item — позиция поставки (товар в документе)
-- Связь M:N между delivery и product, разрешённая через таблицу-связку.
-- quantity и price зависят от пары (delivery_id, product_id) — 2НФ соблюдена.
-- price — цена на момент поставки (исторический снимок, а не ссылка).
-- ---------------------------------------------------------------------
CREATE TABLE delivery_item (
    delivery_item_id SERIAL        PRIMARY KEY,               -- PK (суррогатный)
    delivery_id      INT           NOT NULL REFERENCES delivery(delivery_id) ON DELETE CASCADE, -- FK на поставку
    product_id       INT           NOT NULL REFERENCES product(product_id),                      -- FK на товар
    quantity         NUMERIC(12,3) NOT NULL CHECK (quantity > 0),       -- количество
    price            NUMERIC(12,2) NOT NULL CHECK (price >= 0),         -- цена за единицу на момент поставки
    UNIQUE (delivery_id, product_id)                                 -- товар не дублируется в одной поставке
);

COMMENT ON TABLE  delivery_item                 IS 'Позиции поставки (товар в документе)';
COMMENT ON COLUMN delivery_item.delivery_id     IS 'Ссылка на поставку (FK -> delivery)';
COMMENT ON COLUMN delivery_item.product_id      IS 'Ссылка на товар (FK -> product)';
COMMENT ON COLUMN delivery_item.quantity        IS 'Количество товара';
COMMENT ON COLUMN delivery_item.price           IS 'Цена за единицу на момент поставки';

-- ---------------------------------------------------------------------
-- 8. kiosk_stock — текущий остаток товара в киоске
-- Составной ключ (kiosk_id, product_id): количество зависит от пары
-- «киоск + товар», а не от части ключа (2НФ соблюдена).
-- ---------------------------------------------------------------------
CREATE TABLE kiosk_stock (
    kiosk_id   INT           NOT NULL REFERENCES kiosk(kiosk_id) ON DELETE CASCADE, -- FK на киоск
    product_id INT           NOT NULL REFERENCES product(product_id),                -- FK на товар
    quantity   NUMERIC(12,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),               -- текущий остаток
    PRIMARY KEY (kiosk_id, product_id)                                              -- составной PK
);

COMMENT ON TABLE  kiosk_stock            IS 'Остатки товара в киосках';
COMMENT ON COLUMN kiosk_stock.quantity   IS 'Текущее количество товара в киоске';

-- ---------------------------------------------------------------------
-- Индексы для ускорения типовых запросов (поиск по внешним ключам)
-- ---------------------------------------------------------------------
CREATE INDEX idx_delivery_kiosk        ON delivery(kiosk_id);
CREATE INDEX idx_delivery_supplier     ON delivery(supplier_id);
CREATE INDEX idx_delivery_item_product ON delivery_item(product_id);
CREATE INDEX idx_product_category      ON product(category_id);
CREATE INDEX idx_employee_kiosk        ON employee(kiosk_id);

-- =====================================================================
-- Пример данных для проверки схемы
-- =====================================================================
INSERT INTO category (name) VALUES
    ('Напитки'),
    ('Снеки'),
    ('Хлебобулочные изделия');

INSERT INTO product (name, sku, barcode, unit, purchase_price, retail_price, category_id) VALUES
    ('Кола 0.5л',      'SKU-001', '4600000000011', 'шт', 45.00, 65.00, 1),
    ('Чипсы 100г',     'SKU-002', '4600000000028', 'шт', 38.00, 55.00, 2),
    ('Батон нарезной', 'SKU-003', '4600000000035', 'шт', 22.00, 34.00, 3);

INSERT INTO supplier (name, inn, address, contact_person, phone) VALUES
    ('ООО "Оптовик"',  '7701234567', 'г. Москва, ул. Складская, 1', 'Петров П.П.', '+7 900 111-22-33');

INSERT INTO kiosk (name, address, phone, open_time, close_time) VALUES
    ('Киоск №1', 'ул. Ленина, 10', '+7 900 000-00-01', '08:00', '22:00'),
    ('Киоск №2', 'ул. Мира, 25',    '+7 900 000-00-02', '08:00', '21:00');

INSERT INTO employee (full_name, position, phone, kiosk_id) VALUES
    ('Иванов И.И.', 'Продавец', '+7 900 333-44-55', 1);

INSERT INTO delivery (delivery_number, delivery_date, kiosk_id, supplier_id, responsible_employee_id, status, comment) VALUES
    ('НКЛ-2026-0001', '2026-10-15', 1, 1, 1, 'received', 'Плановая поставка');

INSERT INTO delivery_item (delivery_id, product_id, quantity, price) VALUES
    (1, 1, 50, 45.00),
    (1, 2, 30, 38.00),
    (1, 3, 20, 22.00);

INSERT INTO kiosk_stock (kiosk_id, product_id, quantity) VALUES
    (1, 1, 50),
    (1, 2, 30),
    (1, 3, 20);

-- Проверочные запросы
-- SELECT * FROM delivery d
--   JOIN delivery_item di ON di.delivery_id = d.delivery_id
--   JOIN product p ON p.product_id = di.product_id;
