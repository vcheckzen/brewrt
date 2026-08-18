# LiBwrt IPQ60XX 软件包编译项目（GitHub Actions）

把「你设备上那台固件」当时的完整源码还原出来，用它来编译**任意软件包**（或整机固件），
保证编出来的 `.apk` 和你的固件使用完全相同的工具链 / ABI / feeds，不会出现
之前那种 `Error relocating ...: symbol not found` 的不兼容问题。

- 固件信息：`LiBwrt SNAPSHOT r0-9fd688c`（`qualcommax/ipq60xx`，`aarch64_cortex-a53`，apk 包管理器）
- 源码仓库：<https://github.com/LiBwrt/LibWrt>（原 `LiBwrt/openwrt-6.x`，分支 `kernel-6.12`，现仓库已改名并删掉旧分支）
- 源码 commit：`9fd688ca337da15c6615bde9704b07f56d16c276`
- 原编译项目：<https://github.com/breeze303/openwrt-ci> 的 `0310c1a7`（2025-01-21 最后一次更新）
- 编译日期：2025-01-25 07:56:52 UTC（即设备 `/etc/os-release` 中 `OPENWRT_BUILD_DATE=1737791812`）

## 是怎么定位到源码 hash 的（供你复核）

1. 你贴的 `/etc/os-release` 里有 `BUILD_ID="r0-9fd688c"` → 源码 commit 短 hash = `9fd688c`。
2. `OPENWRT_BUILD_DATE=1737791812` = 2025-01-25 07:56:52 UTC。
3. 在 GitHub 查 `LiBwrt/LibWrt` 的 commit `9fd688c`：
   提交时间正好是 **2025-01-25 07:56:52 UTC**，与固件构建时间戳完全一致，二者互相印证。
4. 该日期前 `breeze303/openwrt-ci` 最后一次提交是 `0310c1a7`，其 `IPQ60XX-6.12-WIFI.yml`
   使用 `LiBwrt/openwrt-6.x` 的 `kernel-6.12` 分支 + `ipq60xx-6.12-wifi.config`，与设备信息吻合。
5. 设备 `VERSION="SNAPSHOT"`（而不是 `24.10-SNAPSHOT`），进一步确认是 6.12 master 线，而非 24.10 线。

## 使用方法

1. 把本目录推到你自己的 GitHub 仓库（新建一个空仓库即可，不用 fork）。
2. 打开 **Actions** → **Build LiBwrt packages for IPQ60XX** → **Run workflow**。
3. 按需填输入项：
   - `source_sha`：源码 commit，默认就是你固件的 `9fd688c...`，一般不用改。
   - `config_flavor`：`wifi` 或 `nowifi`（不清楚就看下面「判断 WIFI/NOWIFI」）。
   - `packages`：要编译的软件包，空格分隔。支持包名（`openssl-util`、`luci-app-passwall`），也支持源码路径（`package/libs/openssl`、`package/feeds/packages/aria2`）；包名会自动解析到对应源码目录，并自动启用进 `.config`（原固件 config 只勾选了固件自带的包，像 `openssl-util` 这种子包原本没被勾选，现在会被自动补上）。填**裸包名**（如 `openssl-util`）只启用该包，依赖由配置系统自动带出；填**目录/路径**（如 `openssl`、`package/libs/openssl`）则启用该目录下所有子包。**留空 = 编译整机固件**。
   - `extra_feeds`：可选，向 `feeds.conf` 追加自定义 feed，每行一条 `src-git xxx https://...`。
   - `nss_packages_sha`：可选，见「注意事项」。
4. 完成后在本次运行的 **Artifacts** 里下载 `apk-wifi` / `apk-nowifi`（编译出的所有 `.apk`）。
   `firmware-wifi` / `firmware-nowifi`（整机固件镜像 + sha256sums + build.config 等）**只在 `packages` 留空时生成**；只编软件包时没有镜像产物，日志里 `No files were found` 属正常提示。
5. 首次运行要先编译主机工具 + 交叉工具链 + 内核，约 2~4 小时；`HiGarfield/cachewrtbuild` 会把编译好的 `staging_dir`（主机工具 + 交叉工具链）和 `ccache` 一起缓存，第二次起命中缓存后直接复用，不再重编工具链；内核（`target/compile`，kmod 类包需要）每次仍会重编，但走 ccache，开启后第一次为冷缓存、之后明显加快。
   `PACKAGES` 非空时，工作流按原固件的编译顺序执行：`make tools/install` → `make toolchain/install` → `make target/compile` → `make package/<目录>/compile`（缓存命中时前两步跳过），所以 kmod-ath11k 这类内核模块包也能编，且与固件内核同源码。

### 安装编译出的包到路由器

```sh
# 先把 .apk 拷到路由器（以 openssl-util 为例）
scp openssl-util_*.apk root@192.168.1.1:/tmp/

# SSH 登录路由器后安装（固件用 apk；产物未签名，需要 --allow-untrusted）
ssh root@192.168.1.1
apk add --allow-untrusted /tmp/openssl-util_*.apk
```

## 在路由器上确认/查看构建 hash

```sh
cat /etc/os-release        # BUILD_ID="r0-9fd688c" ← 构建 hash
cat /etc/openwrt_release   # DISTRIB_REVISION、DISTRIB_TARGET、DISTRIB_ARCH
cat /etc/openwrt_version   # SNAPSHOT
apk info -a base-files     # base-files 完整版本信息
```

设备上只存短 hash。要还原完整 hash，用短 hash 在 GitHub 上查：
```sh
curl -s https://api.github.com/repos/LiBwrt/LibWrt/commits/9fd688c
# 返回 JSON 里的 "sha" 字段就是完整 hash
```

## 判断你的固件是 WIFI 还是 NOWIFI

```sh
apk list -I 2>/dev/null | grep -qi ath11k && echo WIFI || echo NOWIFI
```
输出 `WIFI` 就选 `wifi` 配置，否则选 `nowifi`。（两个配置同一 subtarget，编译用户态软件包时区别不大；只有重编整机固件时才有意义。）

## feeds 锁定（2025-01-25 状态）

`feeds/pinned-6.12.conf` 把当时用的 feed 全部锁死到 2025-01-25 的 commit：

| feed | commit |
| --- | --- |
| immortalwrt/packages | `bf3333594a8add333e3d7192107aa7be8bc39a33` |
| immortalwrt/luci | `be25137852759ada6943e0c2197c5f5faef0c026` |
| openwrt/routing | `4a65e359c301d30b70e448e8c25c6edc9c909be5` |
| openwrt/telephony | `c8a8d621f95ab8be74a1a512c1ce25c50c84e94b` |
| openwrt/video | `44424d479a5383593dfd0aa9e0645a62f0213f75` |
| sbwml/openwrt_pkgs（原工作流额外加入的 netspeedtest/speedtest-cli） | `cce5f6547b70464abacb461e64ec7a4ea1391d11` |

## 注意事项 / 限制

- **nss_packages feed**：源码的 `feeds.conf.default` 里还有
  `src-git nss_packages https://github.com/LiBwrt/nss-packages.git`。该仓库后来被压缩成
  单个提交（2025-11-04），**2025-01-25 的旧内容已无法恢复**，所以默认不加。
  它只影响 NSS 内核/驱动包；编译普通用户态软件不需要。如确需，在 `nss_packages_sha`
  填入唯一现存 commit `959e15c8fbc0...`（注意它是 2025-11 的内容，可能与旧源码不兼容）。
- 内核编译有一个必要补丁：LiBwrt 的 qca-nss-ecm 内核补丁新增了无默认值的
  `CONFIG_NF_CONNTRACK_DSCPREMARK_EXT`，原厂靠 nss feed 里 `kmod-qca-nss-ecm` 的
  `KCONFIG` 注入。由于 nss feed 不可恢复，工作流在最后一次 `make defconfig` 后向
  `.config` 注入 `CONFIG_KERNEL_NF_CONNTRACK_DSCPREMARK_EXT=y`
  （OpenWrt 会把 `CONFIG_KERNEL_*` 映射进内核配置），否则内核 `syncconfig` 会在
  非交互环境询问该符号而失败。
- 产物未签名：安装一律 `apk add --allow-untrusted xxx.apk`。
- ccache 缓存上限为 2G（`CCACHE_MAXSIZE`）；GitHub 仓库缓存总上限 10GB，多次运行会累积时间戳命名的缓存条目，超限后 GitHub 自动按 LRU 驱逐旧缓存，属正常现象。
- 如果某个包不在默认 feeds：用 `extra_feeds` 输入添加，
  或改 `configs/ipq60xx-6.12-wifi.config` / `nowifi` 里的包选择。
- 只编译包时用的仍是整机 `.config`（与原固件一致，保证依赖版本相同）；若某包依赖了
  nss feed 里的专有符号，会编译失败，这也是上面 nss feed 无法恢复带来的唯一副作用。
- 每周任务、定时编译未开启，需要时手动 Run workflow 即可。