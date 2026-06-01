<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:manifest="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
    exclude-result-prefixes="manifest">

    <xsl:param name="new-version"/>

    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="manifest:Identity/@Version">
        <xsl:attribute name="Version">
            <xsl:value-of select="$new-version"/>
        </xsl:attribute>
    </xsl:template>
</xsl:stylesheet>