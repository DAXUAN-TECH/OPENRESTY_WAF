-- ============================================
-- 数据库迁移脚本：修改 waf_proxy_configs 表的 backend_address 和 backend_port 字段为允许 NULL
-- 执行时间：2025-11-27
-- 说明：此脚本用于修改现有数据库，将 backend_address 和 backend_port 字段改为允许 NULL
--       因为现在所有代理都使用 upstream 类型，后端服务器信息存储在 waf_proxy_backends 表中
-- ============================================

-- 检查字段是否已允许 NULL
SET @dbname = DATABASE();
SET @tablename = "waf_proxy_configs";
SET @columnname1 = "backend_address";
SET @columnname2 = "backend_port";

-- 修改 backend_address 字段为允许 NULL
SET @preparedStatement1 = (SELECT IF(
  (
    SELECT IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS
    WHERE
      (TABLE_SCHEMA = @dbname)
      AND (TABLE_NAME = @tablename)
      AND (COLUMN_NAME = @columnname1)
  ) = 'YES',
  "SELECT 'Column backend_address already allows NULL.' AS result;",
  CONCAT("ALTER TABLE ", @tablename, " MODIFY COLUMN ", @columnname1, " VARCHAR(255) DEFAULT NULL COMMENT '后端地址（已废弃：现在使用upstream类型，后端服务器信息存储在waf_proxy_backends表中）';")
));
PREPARE alterIfNotNull1 FROM @preparedStatement1;
EXECUTE alterIfNotNull1;
DEALLOCATE PREPARE alterIfNotNull1;

-- 修改 backend_port 字段为允许 NULL（如果还没有允许）
SET @preparedStatement2 = (SELECT IF(
  (
    SELECT IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS
    WHERE
      (TABLE_SCHEMA = @dbname)
      AND (TABLE_NAME = @tablename)
      AND (COLUMN_NAME = @columnname2)
  ) = 'YES',
  "SELECT 'Column backend_port already allows NULL.' AS result;",
  CONCAT("ALTER TABLE ", @tablename, " MODIFY COLUMN ", @columnname2, " INT UNSIGNED DEFAULT NULL COMMENT '后端端口（已废弃：现在使用upstream类型，后端服务器信息存储在waf_proxy_backends表中）';")
));
PREPARE alterIfNotNull2 FROM @preparedStatement2;
EXECUTE alterIfNotNull2;
DEALLOCATE PREPARE alterIfNotNull2;

-- 验证字段是否修改成功
SELECT 
    COLUMN_NAME,
    COLUMN_TYPE,
    IS_NULLABLE,
    COLUMN_DEFAULT,
    COLUMN_COMMENT
FROM 
    INFORMATION_SCHEMA.COLUMNS
WHERE 
    TABLE_SCHEMA = @dbname
    AND TABLE_NAME = @tablename
    AND COLUMN_NAME IN (@columnname1, @columnname2)
ORDER BY COLUMN_NAME;

