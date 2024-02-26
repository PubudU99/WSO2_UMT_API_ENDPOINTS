-- AUTO-GENERATED FILE.

-- This file is an auto-generated file by Ballerina persistence layer for model.
-- Please verify the generated scripts and execute them against the target DB server.

DROP TABLE IF EXISTS `customers`;

CREATE TABLE `customers` (
	`id` VARCHAR(191) NOT NULL,
	`customer_key` VARCHAR(191) NOT NULL,
	`product_name` VARCHAR(191) NOT NULL,
	`product_base_version` VARCHAR(191) NOT NULL,
	PRIMARY KEY(`id`)
);
