#!/bin/sh
# 精简版 Gradle Wrapper 启动脚本（仅用于 Linux/macOS CI 环境）
# 标准 gradlew 的完整实现依赖大量平台判断逻辑，本项目只在 GitHub Actions 上构建，
# 因此这里保留最小可用实现：定位 wrapper jar，交给已安装的 JVM 执行。

set -e

APP_HOME=$(cd "$(dirname "$0")" && pwd -P)
WRAPPER_JAR="$APP_HOME/gradle/wrapper/gradle-wrapper.jar"

if [ ! -f "$WRAPPER_JAR" ]; then
    echo "ERROR: 缺少 $WRAPPER_JAR" >&2
    exit 1
fi

if [ -n "$JAVA_HOME" ]; then
    JAVA_BIN="$JAVA_HOME/bin/java"
else
    JAVA_BIN=java
fi

exec "$JAVA_BIN" -Xmx64m -Xms64m \
    "-Dorg.gradle.appname=$(basename "$0")" \
    -classpath "$WRAPPER_JAR" \
    org.gradle.wrapper.GradleWrapperMain "$@"
