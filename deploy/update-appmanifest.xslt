<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:manifest="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
    xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
    exclude-result-prefixes="manifest uap">

    <xsl:param name="new-version" />

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

    <xsl:template match="manifest:Application">
        <xsl:copy>
            <xsl:attribute name="Id">
                <xsl:value-of select="/manifest:Package/manifest:Identity/@Name"/>
            </xsl:attribute>
            <xsl:apply-templates select="@*[local-name() != 'Id']|node()"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="uap:VisualElements">
        <xsl:copy>
            <xsl:attribute name="DisplayName">
                <xsl:value-of select="/manifest:Package/manifest:Properties/manifest:DisplayName"/>
            </xsl:attribute>
            <xsl:attribute name="Description">
                <xsl:value-of select="/manifest:Package/manifest:Properties/manifest:Description"/>
            </xsl:attribute>
            <xsl:apply-templates select="@*[local-name() != 'DisplayName' and local-name() != 'Description']|node()"/>
        </xsl:copy>
    </xsl:template>
</xsl:stylesheet>
