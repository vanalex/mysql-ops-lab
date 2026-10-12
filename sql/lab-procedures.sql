-- Inserts a rental and its payment in one call, so Redpanda Connect
-- only needs a single statement per message.
USE sakila;

DROP PROCEDURE IF EXISTS lab_new_rental;

DELIMITER //
CREATE PROCEDURE lab_new_rental(
  IN p_inventory_id MEDIUMINT UNSIGNED,
  IN p_customer_id  SMALLINT UNSIGNED,
  IN p_staff_id     TINYINT UNSIGNED,
  IN p_amount       DECIMAL(5,2)
)
BEGIN
  DECLARE v_rental_id INT;

  START TRANSACTION;
    INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id)
    VALUES (NOW(), p_inventory_id, p_customer_id, p_staff_id);
    SET v_rental_id = LAST_INSERT_ID();

    INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
    VALUES (p_customer_id, p_staff_id, v_rental_id, p_amount, NOW());
  COMMIT;
  -- TODO: handle the rare duplicate on UNIQUE(rental_date, inventory_id, customer_id)
END//
DELIMITER ;
