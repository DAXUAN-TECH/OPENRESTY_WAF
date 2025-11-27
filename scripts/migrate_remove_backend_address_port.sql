-- ============================================
-- 数据库迁移脚本：删除 waf_proxy_configs 表中的 backend_address 和 backend_port 字段
-- 执行时间：2025-11-27
-- 说明：此脚本用于删除已废弃的字段，因为现在所有代理都使用 upstream 类型，
--       后端服务器信息存储在 waf_proxy_backends 表中
-- ============================================

-- 检查字段是否存在，如果存在则删除
SET @dbname = DATABASE();
SET @tablename = "waf_proxy_configs";
SET @columnname1 = "backend_address";
SET @columnname2 = "backend_port";

-- 删除 backend_address 字段（如果存在）
SET @preparedStatement1 = (SELECT IF(
  (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE
      (TABLE_SCHEMA = @dbname)
      AND (TABLE_NAME = @tablename)
      AND (COLUMN_NAME = @columnname1)
  ) > 0,
  CONCAT("ALTER TABLE ", @tablename, " DROP COLUMN ", @columnname1, ";"),
  "SELECT 'Column backend_address does not exist.' AS result;"
));
PREPARE alterIfExists1 FROM @preparedStatement1;
EXECUTE alterIfExists1;
DEALLOCATE PREPARE alterIfExists1;

-- 删除 backend_port 字段（如果存在）
SET @preparedStatement2 = (SELECT IF(
  (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE
      (TABLE_SCHEMA = @dbname)
      AND (TABLE_NAME = @tablename)
      AND (COLUMN_NAME = @columnname2)
  ) > 0,
  CONCAT("ALTER TABLE ", @tablename, " DROP COLUMN ", @columnname2, ";"),
  "SELECT 'Column backend_port does not exist.' AS result;"
));
PREPARE alterIfExists2 FROM @preparedStatement2;
EXECUTE alterIfExists2;
DEALLOCATE PREPARE alterIfExists2;

-- 修改 backend_type 字段的默认值和注释
ALTER TABLE waf_proxy_configs 
MODIFY COLUMN backend_type VARCHAR(20) NOT NULL DEFAULT 'upstream' 
COMMENT '后端类型：upstream-多个后端服务器（负载均衡，只支持此类型）';

-- 验证字段是否删除成功
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
    AND COLUMN_NAME IN (@columnname1, @columnname2, 'backend_type')
ORDER BY COLUMN_NAME;

