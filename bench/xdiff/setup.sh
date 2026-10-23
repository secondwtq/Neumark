#!/usr/bin/env bash
# setup.sh - fetch the xdiff benchmark inputs (idempotent): two versions
# of 35 of the longest single source files in the real world, downloaded
# from pinned commits/tags and SHA-256-verified.
#
#   * intermediates/xdiff/tree/old/   older version of each file
#   * intermediates/xdiff/tree/new/   current version of each file
#
# The benchmark diffs the two "trees" (every changed file, like
# `git diff old_tree new_tree`): ~806k old + ~967k new lines of real
# code across 35 pairs, each spanning multi-year version gaps.
#
#   json/       nlohmann/json v3.5.0 -> v3.12.0
#   ufbx/       ufbx v0.9.0 -> v0.15.1
#   llvm/       X86ISelLowering (llvmorg-11.0.0 -> 19.1.7)
#   clang/      SemaExpr / SemaDecl / ExprConstant (llvmorg-15.0.0 -> 19.1.7)
#   sqlite/     sqlite.h.in + btree.c (3.20.0 -> 3.53.0)
#   sqlite/     sqlite3.c amalgamation (3.20.0 -> 3.53.0, sqlite.org tarballs)
#   v8/         code-stub-assembler / api / liftoff-compiler (@2020 -> @2026)
#   webkit/     DFGSpeculativeJIT64 / DFGSpeculativeJIT / FTLLowerDFGToB3 /
#               WKContentViewInteraction / WebPageProxy / Document / RenderLayer
#               (WebKit-7613.2.6 -> WebKit-7624.4.5)
#   gecko/      Document / ActorsParent (2021-12 -> 2026)
#   gcc/        cp/parser / cp/pt / dwarf2out (gcc-12.2.0 -> gcc-14.2.0)
#   postgres/   tablecmds / pg_dump (REL_15_0 -> REL_18_0)
#   qemu/       mips translate / linux-user syscall / i386 cpu (v7.2.0 -> v9.2.0)
#   dotnet/     coreclr gentree / emitxarch (v7.0.0 -> v9.0.0)
#   swift/      CSSimplify / Decl (swift-5.7 -> swift-6.1)
#   erlang/     beam/erl_process (OTP-25.0 -> OTP-27.0)
#   chromium/   chrome/browser/about_flags (115.0.5790.0 -> 138.0.7188.0)
#
# Applications are set up independently - run this script to prepare
# this application's inputs.
# Usage: setup.sh

set -euo pipefail

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"
mkdir -p "$INT_DIR/tree/old" "$INT_DIR/tree/new" "$INT_DIR/logtree/old" "$INT_DIR/logtree/new"

# fetch_file <url> <sha256> <dest> - download + verify (idempotent)
fetch_file() {
  local url=$1 sha=$2 dest=$3
  if [ ! -f "$dest" ]; then
    echo "== downloading $(basename "$dest") ..."
    curl -sL -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
  fi
  echo "$sha  $dest" | sha256sum -c - > /dev/null
}

# subdir|name|old_url|old_sha256|new_url|new_sha256
PAIRS=(
  "json|json.hpp|https://raw.githubusercontent.com/nlohmann/json/v3.5.0/single_include/nlohmann/json.hpp|8a6dbf3bf01156f438d0ca7e78c2971bca50eec4ca6f0cf59adf3464c43bb9d5|https://raw.githubusercontent.com/nlohmann/json/v3.12.0/single_include/nlohmann/json.hpp|aaf127c04cb31c406e5b04a63f1ae89369fccde6d8fa7cdda1ed4f32dfc5de63"
  "ufbx|ufbx.c|https://raw.githubusercontent.com/ufbx/ufbx/v0.9.0/ufbx.c|c6ac6d41d7a7c9b7bc9d93f0b81c933ab35195ec5e948a40b224b5715baae637|https://raw.githubusercontent.com/ufbx/ufbx/v0.15.1/ufbx.c|e0cbe8bf358b1ba6a304487644fee981e6dc8aecf71faae2c1a0e808317c0ad5"
  "llvm|X86ISelLowering.cpp|https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-11.0.0/llvm/lib/Target/X86/X86ISelLowering.cpp|4a0b1277ae06b27f429f8150a82324dce99858501cbb78d473614cd01bb4599b|https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-19.1.7/llvm/lib/Target/X86/X86ISelLowering.cpp|1abe3e7b4298c3f52dca8c4bc6a40fc3455e534872acadee1cbe2a012c8ce17e"
  "sqlite|sqlite.h.in|https://raw.githubusercontent.com/sqlite/sqlite/version-3.20.0/src/sqlite.h.in|c1d27ec7aacf1b29f162369d0b5def383d7a53154887f5efd321dfd5f148d106|https://raw.githubusercontent.com/sqlite/sqlite/version-3.53.0/src/sqlite.h.in|284f65ed5f4b69ffe838760c4b0cc752787573bd61bf5529415fc663ef1a3022"
  "sqlite|btree.c|https://raw.githubusercontent.com/sqlite/sqlite/version-3.20.0/src/btree.c|e55c1c4b57df22ce1a4f782b8c9b0cfddbf4962fc3858f495b52058f46107bee|https://raw.githubusercontent.com/sqlite/sqlite/version-3.53.0/src/btree.c|5d1c561d09e75971c67bdd0a7401fea94d35a7904b2779c638452fa60d078825"
  "v8|code-stub-assembler.cc|https://raw.githubusercontent.com/v8/v8/7e8a197c370321b29b2bcbce65f8dc84d292a70b/src/codegen/code-stub-assembler.cc|962ada1802d61d169f5c18ef8fa7ec95ead3f191600f7285a91b87f5878d0b80|https://raw.githubusercontent.com/v8/v8/3fa36db0f1a302b883cc8b4732314014901847f5/src/codegen/code-stub-assembler.cc|7ea81d91943c1b304a9c333875d4a2582be1bfe34ede4f610f9c6d96acda6b29"
  "v8|api.cc|https://raw.githubusercontent.com/v8/v8/5ba9362bf9aea5af993ec0f3a3d0fb578565d3aa/src/api/api.cc|458152f6ff4344e38071963fdde4d3af9b46057e8d6757240eba10ab7bed6ab6|https://raw.githubusercontent.com/v8/v8/3fa36db0f1a302b883cc8b4732314014901847f5/src/api/api.cc|15cd09a17edcd25f1d9ecede15bf1457c06e88283f89aa1e66729def243b1098"
  "v8|liftoff-compiler.cc|https://raw.githubusercontent.com/v8/v8/75fa5d421b33b80bbefe165c6ae96d4a6034980f/src/wasm/baseline/liftoff-compiler.cc|f29eabc27f9cdfd9c8b1aa607d4ca1b656c4641f8d7fc3e008b0ccf1eea75f54|https://raw.githubusercontent.com/v8/v8/3fa36db0f1a302b883cc8b4732314014901847f5/src/wasm/baseline/liftoff-compiler.cc|147a5dbd58a3ebcc0445eba445d4da9c180d2fb2a34367b13aa4fa68a7998eac"
  "webkit|DFGSpeculativeJIT64.cpp|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7613.2.6/Source/JavaScriptCore/dfg/DFGSpeculativeJIT64.cpp|2c21de7126bc5513b23cdc40df442f4e2939c5e0a24c8529b7f20bbe4bd5fb5a|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7624.4.5/Source/JavaScriptCore/dfg/DFGSpeculativeJIT64.cpp|d5f965c919c40bf687c4df74f96e30c73ea2d81eca53e368972e60378d4d9d40"
  "webkit|DFGSpeculativeJIT.cpp|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7613.2.6/Source/JavaScriptCore/dfg/DFGSpeculativeJIT.cpp|470c10db685f14300f75c47dfa46f24000cec81b507fa43e33341ff8c245256c|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7624.4.5/Source/JavaScriptCore/dfg/DFGSpeculativeJIT.cpp|2f9ab8b687ba38a7c5d73fe89a0c642f56ad751302d4fa7086b951a6f569844a"
  "webkit|FTLLowerDFGToB3.cpp|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7613.2.6/Source/JavaScriptCore/ftl/FTLLowerDFGToB3.cpp|2d619f4254ce64711f953e7f0890270ea7121fd18ab093be6576e26c4b1badfd|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7624.4.5/Source/JavaScriptCore/ftl/FTLLowerDFGToB3.cpp|1a08fa7e56e8fffd9f8271a995ce2a06ce782f0e8f135a3e263556b6c6f42313"
  "webkit|WKContentViewInteraction.mm|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7613.2.6/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm|d08af292c0b4c5bc947e9e5a61936a67ff21aeee14bd47cb9b43224240ffc641|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7624.4.5/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm|79d33dd46f8670f2713e7a85e10ffabd0465e32d12035f94b6f6e429b8f166d2"
  "webkit|WebPageProxy.cpp|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7613.2.6/Source/WebKit/UIProcess/WebPageProxy.cpp|ff586b17458fee68226d9e2cbdd0233a34d45861c7e74a25599d685a77416c6f|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7624.4.5/Source/WebKit/UIProcess/WebPageProxy.cpp|ebbe702307b4027e0382f320d722400259e8d0817150df2ee5ce2dd38fc11e52"
  "webkit|Document.cpp|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7613.2.6/Source/WebCore/dom/Document.cpp|15221f0eb5172b696fe26ff7ebaa2217ca40f84f11f4656c5c7eb5e64a529c64|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7624.4.5/Source/WebCore/dom/Document.cpp|36b4233758aa43d864da5c831b4bea33a842cf45bd2ea4761d1b52a2638ee559"
  "webkit|RenderLayer.cpp|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7613.2.6/Source/WebCore/rendering/RenderLayer.cpp|7ad6ec3e2aedcfd6240231facbc76973b1ac2aa2eaad5268ccaa411595cbef98|https://raw.githubusercontent.com/WebKit/WebKit/WebKit-7624.4.5/Source/WebCore/rendering/RenderLayer.cpp|0323f027b663684006b1fbf9e861e833bfe92ec2cda6ec8d4ba21bdc99ab55a0"
  "gecko|Document.cpp|https://raw.githubusercontent.com/mozilla/gecko-dev/bdc8d80577f3600fc6ea998ef14372d4e6f6947e/dom/base/Document.cpp|819a4798d316fecdc20b0394f2d744a607163814845cf62dd9dd22a3e1ce09fa|https://raw.githubusercontent.com/mozilla/gecko-dev/5836a062726f715fda621338a17b51aff30d0a8c/dom/base/Document.cpp|7f672ea223e8748d208f1bb4727b4bd89211aba8489e3238ba02f8938b98871a"
  "gecko|ActorsParent.cpp|https://raw.githubusercontent.com/mozilla/gecko-dev/bdc8d80577f3600fc6ea998ef14372d4e6f6947e/dom/indexedDB/ActorsParent.cpp|2172960b4a7a33d1eaa49321fc33f50945bb80e029f3e7d6a933345646cd5ae2|https://raw.githubusercontent.com/mozilla/gecko-dev/5836a062726f715fda621338a17b51aff30d0a8c/dom/indexedDB/ActorsParent.cpp|0cec60739987839a1a772be82b2562984db8016768085947cdcfbb7e0999eb2b"
  "clang|SemaExpr.cpp|https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-15.0.0/clang/lib/Sema/SemaExpr.cpp|2db36501497f1ed002d8b58978afb76c192fc84ad98f8e7e867153c0d9056875|https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-19.1.7/clang/lib/Sema/SemaExpr.cpp|11f36026f1bb326079985e86be9e2ad859267b394520dd452fccf43d02839685"
  "clang|SemaDecl.cpp|https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-15.0.0/clang/lib/Sema/SemaDecl.cpp|e8dd128599b1a72d217486447dc40ee81675d4e889a11ef0e447436ab43fe0b3|https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-19.1.7/clang/lib/Sema/SemaDecl.cpp|08362d8bf6f5f918d200f0f653eca861fb29c6532273af88f5ed3744c2cbd5f0"
  "clang|ExprConstant.cpp|https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-15.0.0/clang/lib/AST/ExprConstant.cpp|1b454e3e0ef92a29bf33c5c77cd5d5f599213d8f71fff8658b4af26f26274f45|https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-19.1.7/clang/lib/AST/ExprConstant.cpp|b5ec5339e949c9240a505e1b8aad5fde23cf75ebfeaf05ce54652193f0ee9927"
  "gcc|parser.cc|https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-12.2.0/gcc/cp/parser.cc|b2c3a843b9b746b0007b51371214603d9db524fbc1d76662b5079f3d4739a9e7|https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-14.2.0/gcc/cp/parser.cc|787dcbce18fc478afbcff0a90d0c851064225cb41ef439846b61e48fa7a47613"
  "gcc|pt.cc|https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-12.2.0/gcc/cp/pt.cc|1be0272d6fe48ae27a2690eceea623b9a0a5b81a28694a0441802c6f72766f04|https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-14.2.0/gcc/cp/pt.cc|b103deea09dcb37d6bec1a0574830b3ebde8ce334f81090518553a3988c548c3"
  "gcc|dwarf2out.cc|https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-12.2.0/gcc/dwarf2out.cc|18c3a021610e406e25d4c3af688c9c9b719c0d1489268b82315521a70e5b314c|https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-14.2.0/gcc/dwarf2out.cc|7074dcfebce0e66a98329c13a304693268bc97914ec32a805bc98f837da24272"
  "postgres|tablecmds.c|https://raw.githubusercontent.com/postgres/postgres/REL_15_0/src/backend/commands/tablecmds.c|99a9f683a574099c235960dfbb0dbb87564817635561b92531b2f1f400cc8723|https://raw.githubusercontent.com/postgres/postgres/REL_18_0/src/backend/commands/tablecmds.c|4a94d6c8083d61512effecce37480ed45ecb10441958fca199562b8cbf55e986"
  "postgres|pg_dump.c|https://raw.githubusercontent.com/postgres/postgres/REL_15_0/src/bin/pg_dump/pg_dump.c|1ac8ffe99435eb0d4784e4a7612bc9e6e92a768d2b52491a9e67718cf81b6944|https://raw.githubusercontent.com/postgres/postgres/REL_18_0/src/bin/pg_dump/pg_dump.c|f70a5395d851c15e66c1dcd7213bca18a33b15e935f4ac1e62f7d3c3736389ec"
  "qemu|translate.c|https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/mips/tcg/translate.c|7298952626536e7147f1a34a488c7c2ca6d638a23cb49cc69b621eeb74acfe47|https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/mips/tcg/translate.c|a3dd0b137fc9bb1f3108fd8763f084c8ce34a6b9269294b5d1c66dd231a5fba0"
  "qemu|syscall.c|https://raw.githubusercontent.com/qemu/qemu/v7.2.0/linux-user/syscall.c|052e666363397f18e466b93b007434f6e84ac65c7f1d3fc6362b1b1c46917d52|https://raw.githubusercontent.com/qemu/qemu/v9.2.0/linux-user/syscall.c|3df7209e9f7f4091cf68c81c5972e94e9cd48da55fee36ca14cf672cb7edc3b5"
  "qemu|cpu.c|https://raw.githubusercontent.com/qemu/qemu/v7.2.0/target/i386/cpu.c|15089f5f5bdd384d71ff404ec98df44ec35047e57207eae3e401143b53ad4bc5|https://raw.githubusercontent.com/qemu/qemu/v9.2.0/target/i386/cpu.c|dbb222d61ace7d53938ca853a18e38850612c7d0bc3dc3ed9402e9133c9c7ce6"
  "dotnet|gentree.cpp|https://raw.githubusercontent.com/dotnet/runtime/v7.0.0/src/coreclr/jit/gentree.cpp|546429cddfc9dcd6d1720048943ae8a5f65b0e61298522934200174431c48123|https://raw.githubusercontent.com/dotnet/runtime/v9.0.0/src/coreclr/jit/gentree.cpp|524cc31c09b5275401db0261571ae63e33e74f1283a0358d5257bf0ba94b7e06"
  "dotnet|emitxarch.cpp|https://raw.githubusercontent.com/dotnet/runtime/v7.0.0/src/coreclr/jit/emitxarch.cpp|b8c88e2b80019d54ef89e5d7402ce02740a92d0b813ca8281d7e213a60d3a1a5|https://raw.githubusercontent.com/dotnet/runtime/v9.0.0/src/coreclr/jit/emitxarch.cpp|0bcc4a4aca51c2e3d4c80d5e3147612e7f10ca04f411fcf0db77d3f13718d86a"
  "swift|CSSimplify.cpp|https://raw.githubusercontent.com/swiftlang/swift/swift-5.7-RELEASE/lib/Sema/CSSimplify.cpp|87243d806c7cc90327b7ed06c9e1324a4a7b352a9896c3eceea7505acecd5937|https://raw.githubusercontent.com/swiftlang/swift/swift-6.1-RELEASE/lib/Sema/CSSimplify.cpp|d7fd048258ea55d8e375de51b19f2eb36a0ad4c89e7029b679028d04d8e28195"
  "swift|Decl.cpp|https://raw.githubusercontent.com/swiftlang/swift/swift-5.7-RELEASE/lib/AST/Decl.cpp|8b320c753862ba333d37140b291cda9b0a87274b64b6f739f12f03e3537673fc|https://raw.githubusercontent.com/swiftlang/swift/swift-6.1-RELEASE/lib/AST/Decl.cpp|955f0c91853e88f34c37778ef665542b992f07ce87ab76f63225a0b1f6dffec2"
  "erlang|erl_process.c|https://raw.githubusercontent.com/erlang/otp/OTP-25.0/erts/emulator/beam/erl_process.c|9c9467742a9d1fd483b074ea1ed4cb9b9accbe9d0bdeaec952d2f92b20a21281|https://raw.githubusercontent.com/erlang/otp/OTP-27.0/erts/emulator/beam/erl_process.c|376fff7f61d847d99350e020387d5697bbc121c2b08848aaa1323e47e0658f25"
  "chromium|about_flags.cc|https://raw.githubusercontent.com/chromium/chromium/115.0.5790.0/chrome/browser/about_flags.cc|9fcde54a911ed983f4a59aaa74ec8ffacc85f7a67e41347f114a526c5293a5b7|https://raw.githubusercontent.com/chromium/chromium/138.0.7188.0/chrome/browser/about_flags.cc|39522dfc63808672482a77c572ae3305f6570401b8e8edb3aaeebf87178b9da2"
  "mame|bfm_sc4.cpp|https://raw.githubusercontent.com/mamedev/mame/mame0221/src/mame/drivers/bfm_sc4.cpp|ef8134ba15b5946d58168a31f455e1876555480cb83930eb8f84d5eeb80086dd|https://raw.githubusercontent.com/mamedev/mame/mame0278/src/mame/bfm/bfm_sc4.cpp|73395a5ded48122c05b4e693c12ea37e8c273ac51125895a549725ba15d7fba6"
  "mame|cps1.cpp|https://raw.githubusercontent.com/mamedev/mame/mame0221/src/mame/drivers/cps1.cpp|8ee2c58d58c50af62deec5942679bfd8202584ecef2b05054e093c8f3cffc52a|https://raw.githubusercontent.com/mamedev/mame/mame0278/src/mame/capcom/cps1.cpp|236b2368b0aad34b25925edfd0395a66b77921dc12e2df65bf9c6884d5d41a14"
  "linux|phy_n.c|https://raw.githubusercontent.com/torvalds/linux/v6.1/drivers/net/wireless/broadcom/brcm80211/brcmsmac/phy/phy_n.c|0b91e9217de6761bb62db957b8a58b98b2857d0537ec9052e8a86a03484df84b|https://raw.githubusercontent.com/torvalds/linux/v6.12/drivers/net/wireless/broadcom/brcm80211/brcmsmac/phy/phy_n.c|1fbb33c4c7bf7d0e70cc0b78aa4796ecd93f51f027dbd547d79917ea016c6512"
  "clickhouse|MergeTreeData.cpp|https://raw.githubusercontent.com/ClickHouse/ClickHouse/v21.8.14.5-lts/src/Storages/MergeTree/MergeTreeData.cpp|9a195912faa487408c34f0099d2be7fd1e2f445b56dfe50c187ccb7d08c9ff4e|https://raw.githubusercontent.com/ClickHouse/ClickHouse/v24.8.5.115-lts/src/Storages/MergeTree/MergeTreeData.cpp|dbf2453d48721ae5be426f48721599892b4c6904a08363cd60246f0c83543dc9"
  "clickhouse|StorageReplicatedMergeTree.cpp|https://raw.githubusercontent.com/ClickHouse/ClickHouse/v21.8.14.5-lts/src/Storages/StorageReplicatedMergeTree.cpp|2700209849874926552b40666c0b794a7082ebd6a8a0e4b7f8126cece002e9e5|https://raw.githubusercontent.com/ClickHouse/ClickHouse/v24.8.5.115-lts/src/Storages/StorageReplicatedMergeTree.cpp|0c250775557a12b60720f904ed669a2ee505a19f92d88ad117a2d5e29df24a2f"
  "libreoffice|svdfppt.cxx|https://raw.githubusercontent.com/LibreOffice/core/libreoffice-7.3.7.2/filter/source/msfilter/svdfppt.cxx|b7ab7c368761297866a46f4f63297893d7cc5851059a05fc84d7d3444fb4b2b2|https://raw.githubusercontent.com/LibreOffice/core/libreoffice-24.8.4.2/filter/source/msfilter/svdfppt.cxx|a757dcf86fa5418ac78039b6f4311c7d515fb71a94751bf22e268ff5cfb62b48"
  "libreoffice|msdffimp.cxx|https://raw.githubusercontent.com/LibreOffice/core/libreoffice-7.3.7.2/filter/source/msfilter/msdffimp.cxx|27a543762a130159d2a96bcdb74614518642956d0ba375e4e7be915e7265f8fd|https://raw.githubusercontent.com/LibreOffice/core/libreoffice-24.8.4.2/filter/source/msfilter/msdffimp.cxx|1f353fd3ca3354467e66ae56506e92d8c3c0c7f305a024ea7e841126ded71a5f"
  "jdk|assembler_x86.cpp|https://raw.githubusercontent.com/openjdk/jdk/jdk-17+35/src/hotspot/cpu/x86/assembler_x86.cpp|e0e770cd7347ecada0331902c9dcd02444e34d7353b9976680f58da5f19b388f|https://raw.githubusercontent.com/openjdk/jdk/jdk-24+36/src/hotspot/cpu/x86/assembler_x86.cpp|c8df8526ff37bb0b000a01931874c416fbfc56cd9c3e8ab1d138c5eaf54356e9"
  "jdk|library_call.cpp|https://raw.githubusercontent.com/openjdk/jdk/jdk-17+35/src/hotspot/share/opto/library_call.cpp|205f50b1ea57970d53290e6d6f0d7a8351898435741167686b0b84ca1e1eca0d|https://raw.githubusercontent.com/openjdk/jdk/jdk-24+36/src/hotspot/share/opto/library_call.cpp|ae10e7d2d19d33e4839302f113b9e28cbbd90d4c6efe24aeb9075fc1675783d8"
  "jdk|Character.java|https://raw.githubusercontent.com/openjdk/jdk/jdk-17+35/src/java.base/share/classes/java/lang/Character.java|677de6733b920f36a78ff8542cb4d605fb61a47dc610c24bc7b98e2b1de95c59|https://raw.githubusercontent.com/openjdk/jdk/jdk-24+36/src/java.base/share/classes/java/lang/Character.java|fc44bbc0a38eb8f8505da433fc9095e6c422d90f5cf1b747afdeeed6eac4eaa4"
  "hermes|JSParserImpl.cpp|https://raw.githubusercontent.com/facebook/hermes/9b93b099b01b40bdb5138d2035eafa27ecaab7a3/lib/Parser/JSParserImpl.cpp|c45062c7bd0c761f2581a3d4d50d7036d6a840fb500891b577e91ddebc4d9a37|https://raw.githubusercontent.com/facebook/hermes/26ec0a0c3959195e75bbbb2ffe27ab5d43873202/lib/Parser/JSParserImpl.cpp|7e53ed7f644b70cf96a5bcfdcfdc81f9e44eec5393be1b8c9510ca67a88cb9d6"
  "hermes|Interpreter.cpp|https://raw.githubusercontent.com/facebook/hermes/9b93b099b01b40bdb5138d2035eafa27ecaab7a3/lib/VM/Interpreter.cpp|e7104c0913cc2edd73c0004392fd1261f6f27a659648573c5ab33f504f276dfa|https://raw.githubusercontent.com/facebook/hermes/26ec0a0c3959195e75bbbb2ffe27ab5d43873202/lib/VM/Interpreter.cpp|8f17650e548d75d84f9d59c00bfefe38145f3f81326a194245063a25d9d5292e"
  "r|eval.c|https://raw.githubusercontent.com/wch/r-source/09eb6982b2110d0878a6cbbf3ababee9923f9b3e/src/main/eval.c|8335e7e33485d3074d7c56155e828e607d1eb93efd5ee90df10ab5bb212c932f|https://raw.githubusercontent.com/wch/r-source/d97d4b41b38065f45f754b7c7966c2bda2dc3534/src/main/eval.c|1280f420c05d76b5373d07d25d08577ae8a0e7f99da9c667b3d2b7936a548507"
  "r|devPS.c|https://raw.githubusercontent.com/wch/r-source/09eb6982b2110d0878a6cbbf3ababee9923f9b3e/src/library/grDevices/src/devPS.c|3ad549f82b98db4247714dccbe10454ed6c2004a13c0a7e68fb20a4c095d340a|https://raw.githubusercontent.com/wch/r-source/d97d4b41b38065f45f754b7c7966c2bda2dc3534/src/library/grDevices/src/devPS.c|3d9eb1e5f13aee0851c0343ae90d269b10bbbeb7c4dfc45b4f229bb25583b191"
  "ffmpeg|mov.c|https://raw.githubusercontent.com/ffmpeg/ffmpeg/n5.0/libavformat/mov.c|a995935c602bbdfeb6cef353327746e3940e3edf2a027d3718097d63010f412d|https://raw.githubusercontent.com/ffmpeg/ffmpeg/n7.0/libavformat/mov.c|3f8eea523e3e7c6485babcc681d0abcfcc0d69020f719b82fc725387be63591c"
  "cataclysm|activity_actor.cpp|https://raw.githubusercontent.com/CleverRaven/Cataclysm-DDA/0.F/src/activity_actor.cpp|504850100fa0dcbfb93872191c651bcda1784b8ad54144e02d291722d8fda965|https://raw.githubusercontent.com/CleverRaven/Cataclysm-DDA/0.H/src/activity_actor.cpp|ed39a344d55de3f200e43ebda59e76cbd0a70f81dd9c3ab5d0c49aa721e175f4"
  "cataclysm|game.cpp|https://raw.githubusercontent.com/CleverRaven/Cataclysm-DDA/0.F/src/game.cpp|eb7fec9c62a4b963ae57cd473f1e7fdc81fe75248d78ca833b8efc7ad4caab48|https://raw.githubusercontent.com/CleverRaven/Cataclysm-DDA/0.H/src/game.cpp|cc51fff60dbaec30cafda0e7a21c12f9831071ff98b4ddd6a643f186eba2d879"
  "cataclysm|map.cpp|https://raw.githubusercontent.com/CleverRaven/Cataclysm-DDA/0.F/src/map.cpp|859b42a1d20eb9cb4ce7f18f6670d1f3801560a8e56ecbd18b9e8ad881012022|https://raw.githubusercontent.com/CleverRaven/Cataclysm-DDA/0.H/src/map.cpp|cef17524cfaec0028ce336d5cf651538e5bb7e8bac4530ac875153f1662979d9"
  "skia|SkRasterPipeline_opts.h|https://raw.githubusercontent.com/google/skia/d88df695a5bf615b38d6b888842d299fbf0826ad/src/opts/SkRasterPipeline_opts.h|262aa343c5336024048359eab93b1c55269a2cbf97b94e79be30dfaae6e3ae83|https://raw.githubusercontent.com/google/skia/47df2ae3226c179ac79dc11e53fb8aeaf2ad9693/src/opts/SkRasterPipeline_opts.h|849ecf600bf6181fc44f101e4c84c451fba13b00f12dbfbe64bd035fc1803541"
  "skia|SkSLSPIRVCodeGenerator.cpp|https://raw.githubusercontent.com/google/skia/d88df695a5bf615b38d6b888842d299fbf0826ad/src/sksl/codegen/SkSLSPIRVCodeGenerator.cpp|87c4dc280fbbcfcd4eb3eae1f357be55ac5552b77a213ac0fb0223af093847eb|https://raw.githubusercontent.com/google/skia/47df2ae3226c179ac79dc11e53fb8aeaf2ad9693/src/sksl/codegen/SkSLSPIRVCodeGenerator.cpp|ce8a2e17b031838abda39f76330498093d65a70eaa52403256a6371981a19393"
  "mariadb|sql_select.cc|https://raw.githubusercontent.com/MariaDB/server/mariadb-10.8.2/sql/sql_select.cc|737fcd42a4d253a4de7f7b382844dd079686158347f1d7ef4762026844e3664a|https://raw.githubusercontent.com/MariaDB/server/mariadb-11.8.1/sql/sql_select.cc|c091b55eea64685ad26096e758506f2662b50118d2596c45a48be75383ad85bb"
  "rust|late.rs|https://raw.githubusercontent.com/rust-lang/rust/1.65.0/compiler/rustc_resolve/src/late.rs|df8342f4c900c04b43a670c2e5ceb6d60b00432652171c2d7de0fa59c2493eea|https://raw.githubusercontent.com/rust-lang/rust/1.87.0/compiler/rustc_resolve/src/late.rs|b950403dbe57ef86722a0624ca7fc589f42a9a10438bb6b166ef917c54d1ccc4"
  "rust|conflict_errors.rs|https://raw.githubusercontent.com/rust-lang/rust/1.65.0/compiler/rustc_borrowck/src/diagnostics/conflict_errors.rs|d9a1d6f928e264d014d2c92f848fe2286b5a4d8af786c1db8b40f81108637d72|https://raw.githubusercontent.com/rust-lang/rust/1.87.0/compiler/rustc_borrowck/src/diagnostics/conflict_errors.rs|35a42ced9e0d4e3a7ccba8d68488d59de7cbfbe22d72ce7f5d6374d2e6534c92"
)

for pair in "${PAIRS[@]}"; do
  IFS='|' read -r subdir name old_url old_sha new_url new_sha <<< "$pair"
  fetch_file "$old_url" "$old_sha" "$INT_DIR/tree/old/$subdir/$name"
  fetch_file "$new_url" "$new_sha" "$INT_DIR/tree/new/$subdir/$name"
done

# sqlite3.c amalgamation - the single biggest source file in the world
# (~204k -> ~269k lines); sqlite.org ships it only inside the autoconf
# tarball (3.20.0 is not on raw.githubusercontent.com).
SQLITE_TARBALLS=(
  "https://sqlite.org/2017/sqlite-autoconf-3200000.tar.gz|3814c6f629ff93968b2b37a70497cfe98b366bf587a2261a56a5f750af6ae6a0|3200000|old"
  "https://sqlite.org/2026/sqlite-autoconf-3530000.tar.gz|851e9b38192fe2ceaa65e0baa665e7fa06230c3d9bd1a6a9662d02380d73365a|3530000|new"
)
for entry in "${SQLITE_TARBALLS[@]}"; do
  IFS='|' read -r url sha ver side <<< "$entry"
  tarball="$INT_DIR/sqlite-autoconf-$ver.tar.gz"
  fetch_file "$url" "$sha" "$tarball"
  if [ ! -f "$INT_DIR/tree/$side/sqlite/sqlite3.c" ]; then
    echo "== extracting sqlite3.c ($ver) ..."
    mkdir -p "$INT_DIR/tree/$side/sqlite" "$INT_DIR/.sqlite-stage"
    # NB: GNU tar matches explicit member names against the name AFTER
    # --strip-components, so extract unstripped and move the file.
    tar -xzf "$tarball" -C "$INT_DIR/.sqlite-stage" "sqlite-autoconf-$ver/sqlite3.c"
    mv "$INT_DIR/.sqlite-stage/sqlite-autoconf-$ver/sqlite3.c" \
      "$INT_DIR/tree/$side/sqlite/sqlite3.c"
    rm -rf "$INT_DIR/.sqlite-stage"
  fi
done

# --- real-world log pairs (intermediates/xdiff/logtree/{old,new}/) -----------
# Long production log files, two time windows each:
#   hdfs.log   HDFS_v1 (11.2M lines, 38.7h) - first half vs second half
#   bgl.log    Blue Gene/L supercomputer (4.7M lines, 214.7 days) - halves
#   nasa.log   NASA web server access logs - July vs August 1995
#   hadoop.log two Hadoop mapreduce container logs (different jobs)
# Sources: logpai/loghub on Zenodo (record 8196385) + ita.ee.lbl.gov.
LOG_ARTIFACTS=(
  "https://zenodo.org/records/8196385/files/HDFS_v1.zip?download=1|04f919f2185821f23f045dca611a7586429bdabc601bd7b43f30005f8e289b01|hdfs.zip|HDFS.log|5588781|54276948421272f0099c16e4d427bf306d1c9f70c34f1b0751c6b5fb4e466322|d1b26f5cc3847134e373ea012913496563ce447ec1b9c787f085bf9d5f414650"
  "https://zenodo.org/records/8196385/files/BGL.zip?download=1|d67fd82a711aea0157a9b83175892c6ee60e384a2ddf5bc51f39118453816da8|bgl.zip|BGL.log|2373981|adab2a1f4ca9819888dc1c2ca1c1866efc7e787f386b8f3cd5f61c9a6256297f|8fec2e29491c56c746ce5259c8bad4c882c9de3d193a454b0fad7b75079820ad"
)
for entry in "${LOG_ARTIFACTS[@]}"; do
  IFS='|' read -r url sha zip log split old_sha new_sha <<< "$entry"
  fetch_file "$url" "$sha" "$INT_DIR/$zip"
  if [ ! -f "$INT_DIR/$log" ]; then
    echo "== extracting $log ..."
    unzip -p "$INT_DIR/$zip" "$log" > "$INT_DIR/$log"
  fi
  for side in old new; do
    dest="$INT_DIR/logtree/$side/${zip%.zip}.log"
    if [ ! -f "$dest" ]; then
      echo "== splitting $log ($side half) ..."
      if [ "$side" = old ]; then
        head -n "$split" "$INT_DIR/$log" > "$dest"
      else
        tail -n "$split" "$INT_DIR/$log" > "$dest"
      fi
    fi
    if [ "$side" = old ]; then want="$old_sha"; else want="$new_sha"; fi
    echo "$want  $dest" | sha256sum -c - > /dev/null
  done
done

# NASA access logs (ita.ee.lbl.gov) - July (old) vs August (new) 1995
NASA=(
  "https://ita.ee.lbl.gov/traces/NASA_access_log_Jul95.gz|199109ed0f273e095da6ccd5fc9dc4cd8bb58daa06d62135e62090fea9d27488|old"
  "https://ita.ee.lbl.gov/traces/NASA_access_log_Aug95.gz|14995aed0ba4558ab832613ebea9a3ef2d87cb4297fc67f5694e0032bbb6b788|new"
)
for entry in "${NASA[@]}"; do
  IFS='|' read -r url sha side <<< "$entry"
  dest="$INT_DIR/logtree/$side/nasa.log"
  if [ ! -f "$dest" ]; then
    echo "== downloading + gunzipping $(basename "$url") ..."
    curl -sL "$url" | gunzip > "$dest"
  fi
  if [ "$side" = old ]; then want="96551161b5bdcaacbc3c17fa108191c478fb35dfe87895c16e34a8f6552bf29a"; else want="c656a5665fcf9c8442bc9e09762de1411f1b97e7bbee65803c6738cdde4cf302"; fi
  echo "$want  $dest" | sha256sum -c - > /dev/null
done

# Hadoop container logs (Zenodo Hadoop.zip) - two different jobs
HADOOP=(
  "application_1445175094696_0003/container_1445175094696_0003_01_000001.log|5a567662a78d8acb37c0243b31a26b4b306e69ffab1ac75ce71ef8e3c3fc2350|old"
  "application_1445144423722_0023/container_1445144423722_0023_01_000001.log|575105327a0520d9c9f9f3771c0886b1279b347f62bcf87495b1ba45e7f9fff6|new"
)
fetch_file "https://zenodo.org/records/8196385/files/Hadoop.zip?download=1" "79e63c6521e90ae164754a29d13e04e0c6c5e782490a7fe1e2b124f4f5737ced" "$INT_DIR/hadoop.zip"
for entry in "${HADOOP[@]}"; do
  IFS='|' read -r member sha side <<< "$entry"
  dest="$INT_DIR/logtree/$side/hadoop.log"
  if [ ! -f "$dest" ]; then
    echo "== extracting $(basename "$member") ..."
    unzip -p "$INT_DIR/hadoop.zip" "$member" > "$dest"
  fi
  echo "$sha  $dest" | sha256sum -c - > /dev/null
done

setup_done
