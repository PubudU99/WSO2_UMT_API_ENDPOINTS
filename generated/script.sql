-- AUTO-GENERATED FILE.

-- This file is an auto-generated file by Ballerina persistence layer for model.
-- Please verify the generated scripts and execute them against the target DB server.

DROP TABLE IF EXISTS `cd_build`;
DROP TABLE IF EXISTS `ci_build`;
DROP TABLE IF EXISTS `cicd_build`;
DROP TABLE IF EXISTS `customer`;

CREATE TABLE `customer` (
	`id` VARCHAR(191) NOT NULL,
	`customer_key` VARCHAR(191) NOT NULL,
	`environment` VARCHAR(191) NOT NULL,
	`product_name` VARCHAR(191) NOT NULL,
	`product_base_version` VARCHAR(191) NOT NULL,
	`u2_level` VARCHAR(191) NOT NULL,
	PRIMARY KEY(`id`)
);

CREATE TABLE `cicd_build` (
	`id` VARCHAR(191) NOT NULL,
	`ci_result` VARCHAR(191) NOT NULL,
	`cd_result` VARCHAR(191) NOT NULL,
	PRIMARY KEY(`id`)
);

CREATE TABLE `ci_build` (
	`id` VARCHAR(191) NOT NULL,
	`ci_build_id` INT NOT NULL,
	`ci_status` VARCHAR(191) NOT NULL,
	`product` VARCHAR(191) NOT NULL,
	`version` VARCHAR(191) NOT NULL,
	`cicd_buildId` VARCHAR(191) NOT NULL,
	FOREIGN KEY(`cicd_buildId`) REFERENCES `cicd_build`(`id`),
	PRIMARY KEY(`id`)
);

CREATE TABLE `cd_build` (
	`id` VARCHAR(191) NOT NULL,
	`cd_build_id` VARCHAR(191) NOT NULL,
	`cd_status` VARCHAR(191) NOT NULL,
	`customer` VARCHAR(191) NOT NULL,
	`cicd_buildId` VARCHAR(191) NOT NULL,
	FOREIGN KEY(`cicd_buildId`) REFERENCES `cicd_build`(`id`),
	PRIMARY KEY(`id`)
);
