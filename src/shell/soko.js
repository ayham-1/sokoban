var statusElement = document.getElementById('status');
var progressElement = document.getElementById('progress');

var Module = {
	preRun: [],
	postRun: [],
	print: (function() {
		var element = document.getElementById('output');
		if (element) element.value = ''; // clear browser cache
		return function(text) {
			if (arguments.length > 1) text = Array.prototype.slice.call(arguments).join(' ');
			console.log(text);
			if (element) {
				element.value += text + "\n";
				element.scrollTop = element.scrollHeight; // focus on bottom
			}
		};
	})(),
	canvas: (function() {
		var canvas = document.getElementById('canvas');
		canvas.addEventListener("webglcontextlost", function(e) { alert('WebGL context lost. You will need to reload the page.'); e.preventDefault(); }, false);

		return canvas;
	})(),
	setStatus: function(text) {
		if (!Module.setStatus.last) Module.setStatus.last = { time: Date.now(), text: '' };
		if (text === Module.setStatus.last.text) return;
		var m = text.match(/([^(]+)\((\d+(\.\d+)?)\/(\d+)\)/);
			var now = Date.now();
			if (m && now - Module.setStatus.last.time < 30) return; // if this is a progress update, skip it if too soon
			Module.setStatus.last.time = now;
			Module.setStatus.last.text = text;
			if (m) {
				text = m[1];
				progressElement.value = parseInt(m[2])*100;
				progressElement.max = parseInt(m[4])*100;
				progressElement.hidden = false;
			} else {
				progressElement.value = null;
				progressElement.max = null;
				progressElement.hidden = true;
			}
		statusElement.innerHTML = text;
	},
	totalDependencies: 0,
	monitorRunDependencies: function(left) {
		this.totalDependencies = Math.max(this.totalDependencies, left);
		Module.setStatus(left ? 'Preparing... (' + (this.totalDependencies-left) + '/' + this.totalDependencies + ')' : 'All downloads complete.');
	}
};

/* code to prevent emscripten compiled code from eating key input */
window.addEventListener('keydown', function(event){
	if (event.keyCode === 8) event.stopImmediatePropagation();
}, true);

window.addEventListener('keyup', function(event){
	if (event.keyCode === 8) event.stopImmediatePropagation();
}, true);

Module.setStatus('Downloading...');
window.onerror = function() {
	Module.setStatus('Exception thrown, try refreshing the page.');
	Module.setStatus = function(text) {
		if (text) console.error('[post-exception status] ' + text);
	};
};

function toggleExtraSettings() {
	var x = document.getElementById("extraSettings");
	if (x.style.display === "none") {
		x.style.display = "block";
	} else {
		x.style.display = "none";
	}
}

function changeMap(element) {
	updateMap = Module.cwrap('updateMap', null, null);
	updateMap();
	element.style.height = "5px";
	element.style.height = (element.scrollHeight)+"px";
}

function focusMap() {
	toggleInput = Module.cwrap('toggleInput', null, null);
	toggleInput();
}
