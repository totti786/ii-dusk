//! A small HTML event tokenizer shaped like Python's `html.parser.HTMLParser` (start/end/data
//! events, lower-cased names, entity-decoded text and attribute values). The scrapers only need
//! events, not a DOM, and the depth bookkeeping in them depends on these exact semantics.
use html_escape::decode_html_entities;

pub type Attrs = Vec<(String, String)>;

pub trait Handler {
    fn start(&mut self, tag: &str, attrs: &Attrs);
    fn end(&mut self, tag: &str);
    fn data(&mut self, text: &str);
}

pub fn attr<'a>(attrs: &'a Attrs, name: &str) -> Option<&'a str> {
    attrs.iter().rev().find(|(k, _)| k == name).map(|(_, v)| v.as_str())
}

pub fn classes(attrs: &Attrs) -> Vec<String> {
    attr(attrs, "class").unwrap_or("").split_whitespace().map(String::from).collect()
}

fn is_ws(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\n' | b'\r' | 0x0c)
}

pub fn feed(html: &str, h: &mut dyn Handler) {
    let b = html.as_bytes();
    let n = b.len();
    let mut i = 0;
    let mut text_start = 0;
    let flush = |from: usize, to: usize, h: &mut dyn Handler| {
        if to > from {
            h.data(&decode_html_entities(&html[from..to]));
        }
    };
    while i < n {
        if b[i] != b'<' {
            i += 1;
            continue;
        }
        let next = b.get(i + 1).copied().unwrap_or(0);
        if next.is_ascii_alphabetic() {
            flush(text_start, i, h);
            let (name, attrs, end, selfclose) = parse_start(html, i + 1);
            h.start(&name, &attrs);
            if selfclose {
                h.end(&name);
            }
            i = end;
            text_start = i;
            if !selfclose && (name == "script" || name == "style") {
                let close = format!("</{name}");
                let lower = html[i..].to_ascii_lowercase();
                let at = lower.find(&close).map(|p| i + p).unwrap_or(n);
                if at > i {
                    h.data(&html[i..at]);
                }
                i = at;
                text_start = i;
            }
        } else if next == b'/' && b.get(i + 2).map(|c| c.is_ascii_alphabetic()).unwrap_or(false) {
            flush(text_start, i, h);
            let mut j = i + 2;
            while j < n && !is_ws(b[j]) && b[j] != b'>' && b[j] != b'/' {
                j += 1;
            }
            let name = html[i + 2..j].to_ascii_lowercase();
            let end = html[j..].find('>').map(|p| j + p + 1).unwrap_or(n);
            h.end(&name);
            i = end;
            text_start = i;
        } else if html[i..].starts_with("<!--") {
            flush(text_start, i, h);
            let end = html[i + 4..].find("-->").map(|p| i + 4 + p + 3).unwrap_or(n);
            i = end;
            text_start = i;
        } else if next == b'!' || next == b'?' {
            flush(text_start, i, h);
            let end = html[i..].find('>').map(|p| i + p + 1).unwrap_or(n);
            i = end;
            text_start = i;
        } else {
            i += 1;
        }
    }
    flush(text_start, n, h);
}

/// Returns (lower-cased name, attributes, index after '>', self-closing).
fn parse_start(html: &str, from: usize) -> (String, Attrs, usize, bool) {
    let b = html.as_bytes();
    let n = b.len();
    let mut i = from;
    while i < n && !is_ws(b[i]) && b[i] != b'>' && b[i] != b'/' {
        i += 1;
    }
    let name = html[from..i].to_ascii_lowercase();
    let mut attrs: Attrs = vec![];
    let mut selfclose = false;
    loop {
        while i < n && (is_ws(b[i]) || b[i] == b'/') {
            if b[i] == b'/' && b.get(i + 1) == Some(&b'>') {
                selfclose = true;
            }
            i += 1;
        }
        if i >= n {
            break;
        }
        if b[i] == b'>' {
            i += 1;
            break;
        }
        let s = i;
        while i < n && !is_ws(b[i]) && b[i] != b'=' && b[i] != b'>' && b[i] != b'/' {
            i += 1;
        }
        let key = html[s..i].to_ascii_lowercase();
        while i < n && is_ws(b[i]) {
            i += 1;
        }
        let mut val = String::new();
        if i < n && b[i] == b'=' {
            i += 1;
            while i < n && is_ws(b[i]) {
                i += 1;
            }
            if i < n && (b[i] == b'"' || b[i] == b'\'') {
                let q = b[i];
                let vs = i + 1;
                let mut j = vs;
                while j < n && b[j] != q {
                    j += 1;
                }
                val = decode_html_entities(&html[vs..j]).into_owned();
                i = (j + 1).min(n);
            } else {
                let vs = i;
                while i < n && !is_ws(b[i]) && b[i] != b'>' {
                    i += 1;
                }
                val = decode_html_entities(&html[vs..i]).into_owned();
            }
        }
        if !key.is_empty() {
            attrs.push((key, val));
        } else {
            i += 1;
        }
    }
    (name, attrs, i, selfclose)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct Rec(Vec<String>);
    impl Handler for Rec {
        fn start(&mut self, t: &str, a: &Attrs) {
            self.0.push(format!("<{t} {}>", a.iter().map(|(k, v)| format!("{k}={v}")).collect::<Vec<_>>().join(",")));
        }
        fn end(&mut self, t: &str) {
            self.0.push(format!("</{t}>"));
        }
        fn data(&mut self, d: &str) {
            self.0.push(format!("'{d}'"));
        }
    }

    #[test]
    fn events() {
        let mut r = Rec::default();
        feed(r#"<DIV class="a b" data-x='1&amp;2' hidden>A &amp; B<br/><!-- c --><script>if (a<b) {}</script></div>"#, &mut r);
        assert_eq!(r.0, ["<div class=a b,data-x=1&2,hidden=>", "'A & B'", "<br >", "</br>", "<script >", "'if (a<b) {}'", "</script>", "</div>"]);
    }
}
