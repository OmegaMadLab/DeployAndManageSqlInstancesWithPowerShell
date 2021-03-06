-- Check extended properties on databases

IF OBJECT_ID(N'#extprops') IS NOT NULL DROP TABLE #extprops

CREATE TABLE #extprops (
    dbname sysname,
    class_desc nvarchar(60),
    [name] sysname,
    [value] sql_variant
)

DECLARE @stmt nvarchar(4000)

SELECT @stmt = ISNULL(@stmt, '') +
			   'IF		(sys.fn_hadr_is_primary_replica(''' + [name] +''') = 1 
				OR	(	SELECT group_database_id 
						FROM sys.databases
						WHERE database_id = ''' + CAST(database_id as nvarchar) + ''' ) IS NULL) 
				BEGIN 
					INSERT INTO #extprops 
					SELECT ''' + [name] + ''' as dbname, class_desc, [name], [value] FROM ' + QUOTENAME(name) + '.sys.extended_properties 
				END;'
FROM sys.databases
WHERE database_id > 4

EXEC sp_executesql @stmt

SELECT * FROM #extprops

DROP TABLE #extprops

-- Set extended properties on databases

Declare @stmt NVARCHAR(4000)

USE [master]

SELECT @stmt = ISNULL(@stmt, '') + 
			   'IF (sys.fn_hadr_is_primary_replica(''' + [name] +''') = 1
				OR	(	SELECT group_database_id 
						FROM sys.databases
						WHERE database_id = ''' + CAST(database_id AS nvarchar) + ''' ) IS NULL) 
				BEGIN 
					EXEC ' + QUOTENAME(Name) + '.sys.sp_addextendedproperty @name=N''Demo'', @value=N''OmegaMadLab''
				END;'
FROM sys.databases
WHERE database_id > 4

EXEC sp_executesql @stmt