import "torque"

tsfunction test() {
    %obj = new ScriptObject(object : inheritor) {
        key = true;
        key1 = "value";
        key3 = (4 + 3) / 2;
    };
}
