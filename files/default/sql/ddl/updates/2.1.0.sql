SET @fk_name = (SELECT CONSTRAINT_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA = "hopsworks" AND TABLE_NAME = "conda_commands" AND REFERENCED_TABLE_NAME="project");
# If fk does not exist, then just execute "SELECT 1"
SET @s = (SELECT IF((@fk_name) is not null,
                    concat('ALTER TABLE hopsworks.conda_commands DROP FOREIGN KEY `', @fk_name, '`'),
                    "SELECT 1"));
PREPARE stmt1 FROM @s;
EXECUTE stmt1;
DEALLOCATE PREPARE stmt1;

ALTER TABLE `hopsworks`.`conda_commands` CHANGE `environment_yml` `environment_file` VARCHAR(1000) COLLATE latin1_general_cs DEFAULT NULL;
ALTER TABLE `hopsworks`.`feature_store_jdbc_connector` ADD UNIQUE INDEX `jdbc_connector_feature_store_id_name` (`feature_store_id`, `name`);

ALTER TABLE `hopsworks`.`feature_store_s3_connector` ADD UNIQUE INDEX `s3_connector_feature_store_id_name` (`feature_store_id`, `name`);
ALTER TABLE `hopsworks`.`feature_store_s3_connector` ADD COLUMN `iam_role` VARCHAR(2048) DEFAULT NULL;
ALTER TABLE `hopsworks`.`feature_store_s3_connector` ADD COLUMN `key_secret_uid` INT DEFAULT NULL;
ALTER TABLE `hopsworks`.`feature_store_s3_connector` ADD COLUMN `key_secret_name` VARCHAR(200) DEFAULT NULL;

ALTER TABLE `hopsworks`.`feature_store_s3_connector`
ADD INDEX `fk_feature_store_s3_connector_1_idx` (`key_secret_uid`, `key_secret_name`);
ALTER TABLE `hopsworks`.`feature_store_s3_connector` ADD CONSTRAINT `fk_feature_store_s3_connector_1`
  FOREIGN KEY (`key_secret_uid` , `key_secret_name`)
  REFERENCES `hopsworks`.`secrets` (`uid` , `secret_name`)
  ON DELETE RESTRICT;

CREATE TABLE `feature_store_redshift_connector` (
  `id` int NOT NULL AUTO_INCREMENT,
  `cluster_identifier` varchar(64) NOT NULL,
  `database_driver` varchar(64) NOT NULL,
  `database_endpoint` varchar(128) DEFAULT NULL,
  `database_name` varchar(64) DEFAULT NULL,
  `database_port` int DEFAULT NULL,
  `table_name` varchar(128) DEFAULT NULL,
  `database_user_name` varchar(128) DEFAULT NULL,
  `auto_create` tinyint(1) DEFAULT 0,
  `database_group` varchar(2048) DEFAULT NULL,
  `iam_role` varchar(2048) DEFAULT NULL,
  `arguments` varchar(2000) DEFAULT NULL,
  `database_pwd_secret_uid` int DEFAULT NULL,
  `database_pwd_secret_name` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_feature_store_redshift_connector_2_idx` (`database_pwd_secret_uid`,`database_pwd_secret_name`),
  CONSTRAINT `fk_feature_store_redshift_connector_2` FOREIGN KEY (`database_pwd_secret_uid`, `database_pwd_secret_name`)
  REFERENCES `hopsworks`.`secrets` (`uid`, `secret_name`) ON DELETE RESTRICT
) ENGINE=ndbcluster DEFAULT CHARSET=latin1 COLLATE=latin1_general_cs;

CREATE TABLE IF NOT EXISTS `feature_store_connector` (
  `id`                      INT(11)          NOT NULL AUTO_INCREMENT,
  `feature_store_id`        INT(11)          NOT NULL,
  `name`                    VARCHAR(150)     NOT NULL,
  `description`             VARCHAR(1000)    NULL,
  `type`                    INT(11)          NOT NULL,
  `jdbc_id`                 INT(11),
  `s3_id`                   INT(11),
  `hopsfs_id`               INT(11),
  `redshift_id`             INT(11),
  PRIMARY KEY (`id`),
  UNIQUE KEY `fs_conn_name` (`name`, `feature_store_id`),
  CONSTRAINT `fs_connector_featurestore_fk` FOREIGN KEY (`feature_store_id`) REFERENCES `hopsworks`.`feature_store` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fs_connector_jdbc_fk` FOREIGN KEY (`jdbc_id`) REFERENCES `hopsworks`.`feature_store_jdbc_connector` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fs_connector_s3_fk` FOREIGN KEY (`s3_id`) REFERENCES `hopsworks`.`feature_store_s3_connector` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fs_connector_hopsfs_fk` FOREIGN KEY (`hopsfs_id`) REFERENCES `hopsworks`.`feature_store_hopsfs_connector` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT `fs_connector_redshift_fk` FOREIGN KEY (`redshift_id`) REFERENCES `hopsworks`.`feature_store_redshift_connector` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE = ndbcluster DEFAULT CHARSET = latin1 COLLATE = latin1_general_cs;

INSERT INTO `feature_store_connector`(`feature_store_id`, `name`, `description`, `type`, `jdbc_id`)
SELECT `feature_store_id`, `name`, `description`, 0, `id` FROM `feature_store_jdbc_connector`;
ALTER TABLE `feature_store_jdbc_connector`
    DROP FOREIGN KEY `jdbc_connector_featurestore_fk`,
    DROP COLUMN `feature_store_id`,
    DROP COLUMN `name`,
    DROP COLUMN `description`;

INSERT INTO `feature_store_connector`(`feature_store_id`, `name`, `description`, `type`, `hopsfs_id`)
SELECT `feature_store_id`, `name`, `description`, 1, `id` FROM `feature_store_hopsfs_connector`;
ALTER TABLE `feature_store_hopsfs_connector`
    DROP FOREIGN KEY `hopsfs_connector_featurestore_fk`,
    DROP COLUMN `feature_store_id`,
    DROP COLUMN `name`,
    DROP COLUMN `description`;

INSERT INTO `feature_store_connector`(`feature_store_id`, `name`, `description`, `type`, `s3_id`)
SELECT `feature_store_id`, `name`, `description`, 2, `id` FROM `feature_store_s3_connector`;
ALTER TABLE `feature_store_s3_connector`
    DROP FOREIGN KEY `s3_connector_featurestore_fk`,
    DROP COLUMN `feature_store_id`,
    DROP COLUMN `name`,
    DROP COLUMN `description`;

ALTER TABLE `on_demand_feature_group` ADD COLUMN `connector_id` int(11), 
    ADD CONSTRAINT `on_demand_conn_fk` FOREIGN KEY (`connector_id`) 
    REFERENCES `hopsworks`.`feature_store_connector` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION;

SET SQL_SAFE_UPDATES = 0;
UPDATE `on_demand_feature_group` `fg` 
SET `fg`.`connector_id` = (SELECT `id` FROM `feature_store_connector` `fc` 
WHERE `fc`.`jdbc_id` = `fg`.`jdbc_connector_id`);
SET SQL_SAFE_UPDATES = 1;

ALTER TABLE `on_demand_feature_group` DROP FOREIGN KEY `on_demand_fg_jdbc_fk`,
    DROP COLUMN `jdbc_connector_id`;

ALTER TABLE `external_training_dataset` ADD COLUMN `connector_id` int(11), 
    ADD CONSTRAINT `ext_td_conn_fk` FOREIGN KEY (`connector_id`) 
    REFERENCES `hopsworks`.`feature_store_connector` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION;

SET SQL_SAFE_UPDATES = 0;
UPDATE `external_training_dataset` `fg` 
SET `fg`.`connector_id` = (SELECT `id` FROM `feature_store_connector` `fc` 
WHERE `fc`.`s3_id` = `fg`.`s3_connector_id`);
SET SQL_SAFE_UPDATES = 1;

ALTER TABLE `external_training_dataset` DROP FOREIGN KEY `external_td_s3_connector_fk`,
    DROP COLUMN `s3_connector_id`;

ALTER TABLE `hopsfs_training_dataset` ADD COLUMN `connector_id` int(11), 
    ADD CONSTRAINT `hopsfs_td_conn_fk` FOREIGN KEY (`connector_id`) 
    REFERENCES `hopsworks`.`feature_store_connector` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION;

SET SQL_SAFE_UPDATES = 0;
UPDATE `hopsfs_training_dataset` `fg` 
SET `fg`.`connector_id` = (SELECT `id` FROM `feature_store_connector` `fc` 
WHERE `fc`.`hopsfs_id` = `fg`.`hopsfs_connector_id`);
SET SQL_SAFE_UPDATES = 1;

ALTER TABLE `hopsfs_training_dataset` DROP FOREIGN KEY `hopsfs_td_connector_fk`,
    DROP COLUMN `hopsfs_connector_id`;

CREATE TABLE `cached_feature_extra_constraints` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `cached_feature_group_id` int(11) NULL,
  `name` varchar(63) COLLATE latin1_general_cs NOT NULL,
  `primary_column` tinyint(1) NOT NULL DEFAULT '0',
  `hudi_precombine_key` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `cached_feature_group_fk` (`cached_feature_group_id`),
  CONSTRAINT `cached_feature_group_fk1` FOREIGN KEY (`cached_feature_group_id`) REFERENCES `cached_feature_group` (`id`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=ndbcluster DEFAULT CHARSET=latin1 COLLATE=latin1_general_cs;
