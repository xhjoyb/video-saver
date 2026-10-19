Java.perform(function () {
  var VIDEO = 'com.ss.android.ugc.aweme.feed.model.Video';
  var VUM = 'com.ss.android.ugc.aweme.feed.model.VideoUrlModel';

  function dumpModel(tag, m) {
    try {
      if (!m) { return; }
      var uri = '';
      try { uri = String(m.getUri()); } catch (e) {}
      var urls = [];
      try {
        var list = m.getUrlList();
        if (list) {
          for (var i = 0; i < list.size() && i < 8; i++) {
            urls.push(String(list.get(i)));
          }
        }
      } catch (e) {}
      if (uri || urls.length) {
        console.log(tag + ' uri=' + uri + ' urls=' + JSON.stringify(urls));
      }
    } catch (e) {
      console.log('DUMP_ERR ' + e);
    }
  }

  try {
    var V = Java.use(VIDEO);
    var all = V.class.getDeclaredMethods();
    var names = [];
    for (var i = 0; i < all.length; i++) { names.push(all[i].getName()); }
    console.log('VIDEO_METHODS ' + JSON.stringify(names));

    var targets = [];
    for (var j = 0; j < all.length; j++) {
      if (all[j].getReturnType().getName() === VUM) {
        var n = all[j].getName();
        if (targets.indexOf(n) < 0) { targets.push(n); }
      }
    }
    console.log('VUM_RETURNERS ' + JSON.stringify(targets));

    targets.forEach(function (mn) {
      try {
        V[mn].overloads.forEach(function (ov) {
          ov.implementation = function () {
            var r = ov.apply(this, arguments);
            dumpModel('PLAY ' + mn, r);
            return r;
          };
        });
      } catch (e) {
        console.log('HOOK_FAIL ' + mn + ' ' + e);
      }
    });
    console.log('HOOK_DONE ' + targets.length);
  } catch (e) {
    console.log('VIDEO_CLASS_FAIL ' + e);
  }
});