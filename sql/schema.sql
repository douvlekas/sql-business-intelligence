-- =====================================================================
-- E-shop for agricultural products: database & business intelligence
-- MySQL 8
-- Author: Georgios Douvlekas - MSc Business Mathematics (NKUA & AUEB)
-- =====================================================================

CREATE DATABASE IF NOT EXISTS eshop_db;
USE eshop_db;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

-- Customers: core customer master data
CREATE TABLE Customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name   VARCHAR(100) NOT NULL,
    email       VARCHAR(100) UNIQUE,
    phone       VARCHAR(20),
    address     VARCHAR(255),
    country     VARCHAR(50)
);

-- Products: catalogue with price and available stock
CREATE TABLE Products (
    product_id INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    category   VARCHAR(50),
    weight     VARCHAR(20),               -- e.g. '500g', '1kg'
    price      DECIMAL(10, 2) NOT NULL,   -- DECIMAL for monetary precision
    stock      INT DEFAULT 0
);

-- Orders: order header linking a customer to a purchase
CREATE TABLE Orders (
    order_id     INT AUTO_INCREMENT PRIMARY KEY,
    customer_id  INT,
    order_date   DATETIME DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10, 2) DEFAULT 0.00,
    FOREIGN KEY (customer_id) REFERENCES Customers(customer_id)
);

-- OrderItems: order lines (many-to-many between Orders and Products)
CREATE TABLE OrderItems (
    order_item_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id      INT,
    product_id    INT,
    quantity      INT NOT NULL,
    unit_price    DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (order_id)   REFERENCES Orders(order_id),
    FOREIGN KEY (product_id) REFERENCES Products(product_id)
);

-- SalesStats: daily sales summary table
CREATE TABLE SalesStats (
    statDate   DATE PRIMARY KEY,
    totalSales DECIMAL(10, 2)
);

-- ---------------------------------------------------------------------
-- Sample data
-- ---------------------------------------------------------------------
INSERT INTO Customers (full_name, email, phone, address, country) VALUES
('George Papadopoulos', 'gpapadop@email.com', '000000001', '12 Aiolou St, Athens',      'Greece'),
('Maria Antoniou',      'mantoniou@email.com','000000002', '45 Tsimiski St, Thessaloniki','Greece'),
('John Athanasiou',     'jath@email.com',     '000000003', '34 Ag. Andrea St, Patras',  'Greece');

INSERT INTO Products (name, category, weight, price, stock) VALUES
('Lentils',                 'legumes', '500g', 4.50, 50),
('Chickpeas',               'legumes', '1kg',  3.20, 0),
('Thyme Honey',             'honey',   '1kg', 14.00, 20),
('Wildflower Honey',        'honey',   '500g', 7.50, 35),
('Extra Virgin Olive Oil',  'oil',     '5L',  45.00, 15),
('Hilopites (egg noodles)', 'pasta',   '500g', 4.00, 40),
('Trahanas',                'pasta',   '500g', 4.50, 30);

-- Historical orders (customer 1 exceeds EUR 200 to test the loyalty rule)
INSERT INTO Orders (customer_id, order_date, total_amount) VALUES
(1, '2023-05-10 10:00:00', 135.00),
(1, '2023-09-15 14:30:00',  90.00),
(2, '2023-11-20 09:15:00',  45.00);

INSERT INTO OrderItems (order_id, product_id, quantity, unit_price) VALUES
(1, 5, 3, 45.00),
(2, 5, 2, 45.00),
(3, 5, 1, 45.00);

-- Today's order (used to test the TodaysOrders view)
INSERT INTO Orders (customer_id, order_date, total_amount) VALUES
(3, NOW(), 28.00);

INSERT INTO OrderItems (order_id, product_id, quantity, unit_price) VALUES
(4, 3, 2, 14.00);

-- ---------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------

-- 1. Products currently in stock
CREATE VIEW AvailableProducts AS
SELECT name, category, price, stock
FROM Products
WHERE stock > 0;

-- 2. Orders placed today
CREATE VIEW TodaysOrders AS
SELECT o.order_id, c.full_name, c.email, o.total_amount
FROM Orders o
JOIN Customers c ON o.customer_id = c.customer_id
WHERE DATE(o.order_date) = CURDATE();

-- 3. Customers ranked by total spend
CREATE VIEW TopCustomers AS
SELECT c.full_name, SUM(o.total_amount) AS total_spent
FROM Customers c
JOIN Orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.full_name
ORDER BY total_spent DESC;

-- 4. Line-level invoice data (feeds the Excel invoice and the Python analysis)
CREATE VIEW InvoiceData AS
SELECT
    c.full_name                   AS customer,
    c.email                       AS email,
    c.address                     AS address,
    o.order_id                    AS order_id,
    o.order_date                  AS order_date,
    p.name                        AS product,
    oi.quantity                   AS quantity,
    oi.unit_price                 AS unit_price,
    (oi.quantity * oi.unit_price) AS line_total
FROM Customers c
JOIN Orders     o  ON c.customer_id = o.customer_id
JOIN OrderItems oi ON o.order_id    = oi.order_id
JOIN Products   p  ON oi.product_id = p.product_id;

-- ---------------------------------------------------------------------
-- Trigger: on every new order line
--   (a) automatically reduce product stock
--   (b) apply a 10% loyalty discount if the customer spent > EUR 200
--       in the last 12 months
-- ---------------------------------------------------------------------
DELIMITER //

CREATE TRIGGER process_new_order_item
BEFORE INSERT ON OrderItems
FOR EACH ROW
BEGIN
    DECLARE past_year_total DECIMAL(10, 2);
    DECLARE current_customer_id INT;

    -- Identify the customer placing the order
    SELECT customer_id INTO current_customer_id
    FROM Orders
    WHERE order_id = NEW.order_id;

    -- Customer spend over the last 12 months (0 if no purchases)
    SELECT COALESCE(SUM(total_amount), 0) INTO past_year_total
    FROM Orders
    WHERE customer_id = current_customer_id
      AND order_date >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR);

    -- (b) Loyalty discount
    IF past_year_total > 200 THEN
        SET NEW.unit_price = NEW.unit_price * 0.90;
    END IF;

    -- (a) Inventory update
    UPDATE Products
    SET stock = stock - NEW.quantity
    WHERE product_id = NEW.product_id;
END //

DELIMITER ;

-- ---------------------------------------------------------------------
-- Scheduled event: every day at 00:05, store the previous day's sales
-- in SalesStats (requires: SET GLOBAL event_scheduler = ON;)
-- ---------------------------------------------------------------------
DELIMITER //

CREATE EVENT IF NOT EXISTS daily_sales_summary
ON SCHEDULE EVERY 1 DAY
STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 5 MINUTE)
DO
BEGIN
    INSERT INTO SalesStats (statDate, totalSales)
    SELECT
        DATE_SUB(CURDATE(), INTERVAL 1 DAY),   -- previous day
        COALESCE(SUM(total_amount), 0)         -- total sales (0 if none)
    FROM Orders
    WHERE DATE(order_date) = DATE_SUB(CURDATE(), INTERVAL 1 DAY);
END //

DELIMITER ;
