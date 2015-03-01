module Control.Asap.Node where

import Control.Monad.Eff

foreign import data Asap :: !

--| Takes an effect of type `Eff e Unit` and executes it as soon as possible,
--| but after the current event has completed, and after previously
--| scheduled jobs.
foreign import schedule """
var domain;
var hasSetImmediate = typeof setImmediate === "function";
function rawAsap(task) {
    if (!queue.length) {
        requestFlush();
        flushing = true;
    }
    // Avoids a function call
    queue[queue.length] = task;
}
var queue = [];
var flushing = false;
var index = 0;
var capacity = 1024;
function flush() {
    while (index < queue.length) {
        var currentIndex = index;
        index = index + 1;
        queue[currentIndex].call();
        if (index > capacity) {
            for (var scan = 0; scan < index; scan++) {
                queue[scan] = queue[scan + index];
            }
            queue.length -= index;
            index = 0;
        }
    }
    queue.length = 0;
    index = 0;
    flushing = false;
}

rawAsap.requestFlush = requestFlush;
function requestFlush() {
    var parentDomain = process.domain;
    if (parentDomain) {
        if (!domain) {
            domain = require("domain");
        }
        domain.active = process.domain = null;
    }
    if (flushing && hasSetImmediate) {
        setImmediate(flush);
    } else {
        process.nextTick(flush);
    }
    if (parentDomain) {
        domain.active = process.domain = parentDomain;
    }
}

var freeTasks = [];
function asap(task) {
    var rawTask;
    if (freeTasks.length) {
        rawTask = freeTasks.pop();
    } else {
        rawTask = new RawTask();
    }
    rawTask.task = task;
    rawTask.domain = process.domain;
    rawAsap(rawTask);
}

function RawTask() {
    this.task = null;
    this.domain = null;
}

RawTask.prototype.call = function () {
    if (this.domain) {
        this.domain.enter();
    }
    var threw = true;
    try {
        this.task.call();
        threw = false;
        if (this.domain) {
            this.domain.exit();
        }
    } finally {
        if (threw) {
            rawAsap.requestFlush();
        }
        this.task = null;
        this.domain = null;
        freeTasks.push(this);
    }
};

function schedule(task) {
  return function() {
    asap(task);
  };
}""" :: forall e. Eff (asap :: Asap | e) Unit -> Eff (asap ::Asap | e) Unit